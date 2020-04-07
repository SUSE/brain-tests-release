#!/usr/bin/env ruby

require_relative 'testutils'
require 'fileutils'
require 'json'

Timeout::timeout(ENV.fetch('TESTBRAIN_TIMEOUT', '600').to_i - 60) do
  # the timeout stuff isn't necessary, it just gives it time to clean up

  login
  setup_org_space

  CF_TCP_DOMAIN = ENV.fetch('CF_TCP_DOMAIN', random_suffix('tcp') + ENV['CF_DOMAIN'])
  CF_SEC_GROUP = random_suffix('sg', 'CF_SEC_GROUP')

  at_exit do
    set errexit: false do
      run "cf delete-security-group -f #{CF_SEC_GROUP}"
    end
  end

  tmpdir = mktmpdir

  File.open("#{tmpdir}/secgroup.json", 'w') do |f|
    f.puts [ { destination: '0.0.0.0/0', protocol: 'all' } ].to_json
  end
  run "cf create-security-group #{CF_SEC_GROUP} #{tmpdir}/secgroup.json"
  run "cf bind-security-group #{CF_SEC_GROUP} #{$CF_ORG} #{$CF_SPACE} --lifecycle staging"
  run "cf bind-security-group #{CF_SEC_GROUP} #{$CF_ORG} #{$CF_SPACE} --lifecycle running"

  # Defered: 'secure-registry'   => "https://secure-registry.#{ENV['CF_DOMAIN']}",          # Router SSL cert
  # See ticket https://github.com/cloudfoundry-incubator/kubecf/issues/466
  # Also see   https://github.com/cloudfoundry-incubator/kubecf/issues/424
  REGISTRIES = {
    'insecure-registry' => "https://#{CF_TCP_DOMAIN}:20005"     # Self-signed SSL cert
  }

  at_exit do
    set errexit: false do
      REGISTRIES.each_key do |registry|
        run "cf delete -f #{registry}"
      end
      run "cf delete-route -f #{ENV['CF_DOMAIN']} --hostname secure-registry"
      run "cf delete-route -f #{CF_TCP_DOMAIN} --port 20005"
      run "cf delete-shared-domain -f #{CF_TCP_DOMAIN}"
    end
  end

  # set up tcp routing for the invalid-cert registry
  set errexit: false do
    run "cf delete-shared-domain -f #{CF_TCP_DOMAIN}"
  end

  run "cf create-shared-domain #{CF_TCP_DOMAIN} --router-group default-tcp"
  run "cf update-quota default --reserved-route-ports -1"

  puts "deploy ...................................................................."

  # Deploy the registry ... Assemble the apps for push
  FileUtils::Verbose.cp resource_path('docker-uploader/manifest.yml'),
                        '/var/vcap/packages/docker-distribution/manifest.yml'
  FileUtils::Verbose.cp resource_path('docker-uploader/config.yml'),
                        '/var/vcap/packages/docker-distribution/config.yml'
  FileUtils::Verbose.cp '/var/vcap/packages/acceptance-tests-brain/bin/docker-uploader',
                        '/var/vcap/packages/docker-distribution/bin/'
  FileUtils::Verbose.cp '/var/vcap/packages/acceptance-tests-brain/bin/registry',
                        '/var/vcap/packages/docker-distribution/bin/'
  at_exit do
    set errexit: false do
      puts "........................................................................... SHUTDOWN"
      %w(secure-registry insecure-registry uploader).each do |app|
        run "cf logs --recent #{app}"
        run "cf delete -f #{app}"
      end
    end
  end
  run "cf push -f manifest.yml --var tcp-domain=#{CF_TCP_DOMAIN}",
      chdir: '/var/vcap/packages/docker-distribution/'

  run 'cf apps'

  # Wait a bit to have the log tailer thread start properly and settle before doing more.
  sleep 5

  REGISTRIES.each_pair do |regname, registry_url|
    puts "wait for registry to be available ......................................... #{regname}"
    # Wait for the registry to be available
    run_with_retry 60, 1 do
      run "curl --fail -kv #{registry_url}/v2/"
    end
  end
  run_with_retry 60, 1 do
    run "curl --fail -kv http://uploader.#{ENV['CF_DOMAIN']}"
  end

  REGISTRIES.each_pair do |regname, registry_url|
    puts "upload uploader ........................................................... #{regname}"
    begin
      run "curl --fail http://uploader.#{ENV['CF_DOMAIN']} -d registry=#{registry_url} -d name=image"
    rescue
      set errexit: false do
        puts "upload uploader ........................................................... #{regname} FAIL"
        run 'cf apps'
        run "cf logs --recent uploader   | sed -e 's/^/UPLOADER: /'"
        run "cf logs --recent #{regname} | sed -e 's/^/#{regname}: /'"
      end
      raise
    end
    # Wait a bit for the log tailers to flush stuff
    sleep 5
    run "cf logs --recent uploader | sed -e 's/^/UPLOADER: /'"
  end

  caught_error = nil

  REGISTRIES.each_pair do |regname, registry_url|
    puts "uploader as docker app .................................................... #{regname}"
    begin
      registry = registry_url.sub %r#^https://#, ''
      run "cf push from-#{regname} --docker-image #{registry}/image:latest"
    rescue RuntimeError => e
      caught_error = e
      set errexit: false do
        run "cf logs --recent from-#{regname}"
        run "cf logs --recent uploader   | sed -e 's/^/UPLOADER: /'"
        run "cf logs --recent #{regname} | sed -e 's/^/#{regname}: /'"
      end
    ensure
      set errexit: false do
        run "cf delete -f from-#{regname}"
      end
    end
  end

  puts "..........................................................................."
  raise caught_error if caught_error
end
