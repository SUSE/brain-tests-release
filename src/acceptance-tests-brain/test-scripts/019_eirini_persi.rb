#!/usr/bin/env ruby

# __Attention__
# This tests assumes that the kernel modules `nfs` and `nfsd` are
# already loaded.

require 'json'
require 'yaml'

require_relative 'testutils'

exit_skipping_test if ENV['EIRINIPERSI_ENABLED'] != 'true'

use_global_timeout

login
setup_org_space

NS = ENV['KUBERNETES_NAMESPACE']

APP_NAME = random_suffix('persitest')
VOLUME_NAME = random_suffix('eirini-persi')
BROKER_URL = 'http://eirini-persi-broker:8999'

tmpdir = mktmpdir

at_exit do
    set errexit: false do
        # Status of the pods in the namespace
        show_pods_for_namespace NS

        # See why persitest failed to start
        run "cf logs #{APP_NAME} --recent"

        # Delete the app, the associated service, block it from use again
        run "cf delete -f #{APP_NAME}"
        run "cf delete-route -f '#{ENV['DOMAIN']}' --hostname #{APP_NAME}"
        run "cf delete-service -f #{VOLUME_NAME}"
        run "cf disable-service-access eirini-persi"
    end
end

BROKER_PASS = capture("kubectl get secrets -n kubecf -o json persi-broker-auth-password | jq -r '.data.\"password\"' | base64 -d").strip

run "cf create-service-broker eirini-persi admin #{BROKER_PASS} #{BROKER_URL}"

run "cf push #{APP_NAME} --no-start", chdir: resource_path('eirini-persi-app')

run "cf enable-service-access eirini-persi"

run "cf create-service eirini-persi default #{VOLUME_NAME}"

run %Q@cf bind-service #{APP_NAME} #{VOLUME_NAME}@

run "cf start #{APP_NAME}"

APP_URL = "#{APP_NAME}.#{ENV['CF_DOMAIN']}"

# Test that the app is available
run "curl #{APP_URL} | grep '1'"

run "cf restage #{APP_NAME}"

# Test that the app can write to the volume of the bound service
run "curl #{APP_URL} | grep '0'"
