#!/usr/bin/env ruby

require_relative 'testutils'

exit_skipping_test if ENV['PUSHAPP_ENABLED'] != 'true'

login
setup_org_space

app = resource_path('node-env')
app_name = random_suffix('node-env')

at_exit do
    set errexit: false do
        run "cf delete -f #{app_name}"
    end
end

run "cf push #{app_name} -p #{app}"
