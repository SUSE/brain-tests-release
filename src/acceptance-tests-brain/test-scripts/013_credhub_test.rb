#!/usr/bin/env ruby

require 'base64'
require 'json'

require_relative 'testutils'

CH_CLI = 'credhub'
CH_SERVICE = "https://credhub.#{ENV['CF_DOMAIN']}"

# Check if credhub is running, otherwise skip the test.  We do not
# break on the first failure, but check a bit more, in case it was a
# transient issue with the endpoint. We do accept success immediately,
# though.

# Initialize status outside of loop block to be able to check after loop ends.
status = run_with_status('true');
10.times do
  status = run_with_status('curl', '--silent', '--fail', '--insecure', "#{CH_SERVICE}/info")
  break if status.success?
  sleep 1
end
exit_skipping_test unless status.success?

login

# Skip the test if we do not have credhub auth set up
exit_skipping_test unless ENV['CREDHUB_CLIENT'] && ENV['CREDHUB_SECRET']
run CH_CLI, 'api', '--skip-tls-validation', CH_SERVICE
run CH_CLI, 'login',
    "--client-name=#{ENV['CREDHUB_CLIENT']}",
    "--client-secret=#{ENV['CREDHUB_SECRET']}",
    xtrace: false

tmpdir = mktmpdir

# Insert ...
run "#{CH_CLI} set -n FOX -t value -v 'fox over lazy dog' > #{tmpdir}/fox"
run "#{CH_CLI} set -n DOG -t user -z dog -w fox           > #{tmpdir}/dog"

# Retrieve ...
run "#{CH_CLI} get -n FOX > #{tmpdir}/fox2"
run "#{CH_CLI} get -n DOG > #{tmpdir}/dog2"

# Show (in case of failure) ...
%w(fox fox2 dog dog2).each do |filename|
    puts "__________________________________ #{filename}"
    run "cat #{tmpdir}/#{filename}"
end
puts "__________________________________"

# Check ...

run "grep 'name: /FOX'        #{tmpdir}/fox"
run "grep 'type: value'       #{tmpdir}/fox"
run "grep 'value: <redacted>' #{tmpdir}/fox"

run "grep 'name: /FOX'               #{tmpdir}/fox2"
run "grep 'type: value'              #{tmpdir}/fox2"
run "grep 'value: fox over lazy dog' #{tmpdir}/fox2"

id = File.open("#{tmpdir}/fox") do |f|
    f.each_line.find{ |line| line.start_with? 'id:' }.split[1]
end
run "grep '^id: #{id}$' #{tmpdir}/fox2"

run "grep 'name: /DOG'        #{tmpdir}/dog"
run "grep 'type: user'        #{tmpdir}/dog"
run "grep 'value: <redacted>' #{tmpdir}/dog"

run "grep 'name: /DOG'        #{tmpdir}/dog2"
run "grep 'type: user'        #{tmpdir}/dog2"

id = File.open("#{tmpdir}/dog") do |f|
    f.each_line.find{ |line| line.start_with? 'id:' }.split[1]
end
run "grep '^id: #{id}$' #{tmpdir}/dog2"

run "grep 'password: fox' #{tmpdir}/dog2"
run "grep 'username: dog' #{tmpdir}/dog2"

# Not checking the `password_hash` (it is expected to change from run
# to run, due to random seed changes, salting)
#
# Similarly, `version_created_at` is an ever changing timestamp.
