#!/usr/bin/env ruby

require_relative 'minibroker_helper'

$DB_NAME = random_suffix('db')

tester = MiniBrokerTest.new('mariadb', '3306')
tester.service_params = {
    db: { name: $DB_NAME },
    # Need "mariadbDatabase" key for compatibility with old minibroker.
    mariadbDatabase: $DB_NAME,
    master: { persistence: { storageClass: storage_class } },
    slave: { persistence: { storageClass: storage_class } },
}
tester.run_test do |tester|
    CF_APP = random_suffix('app', 'CF_APP')

    at_exit do
        set errexit: false do
            run "cf logs --recent #{CF_APP}"
            run "cf env #{CF_APP}"
            run "cf unbind-service #{CF_APP} #{tester.service_instance}"
            run "cf delete -f #{CF_APP}"
        end
    end

    # Create an app bound to the service under test, and start it.
    run 'cf', 'push', CF_APP,
        '--no-start',
        '-p', resource_path('rails-example'),
        '--no-manifest',
        '-m', '256M',
        '-c', 'bundle exec rake db:migrate && bundle exec rails s -p $PORT'
    run "cf bind-service #{CF_APP} #{tester.service_instance}"
    run "cf start #{CF_APP}"

    # Wait for the app to be staged and started.
    app_guid = capture("cf app #{CF_APP} --guid")
    puts "# app GUID: #{app_guid}"
    STDOUT.flush
    run_with_retry 60, 10 do
        app_info = JSON.load capture("cf curl '/v2/apps/#{app_guid}'")
        puts "# app info: #{app_info}"
        STDOUT.flush
        break if app_info['entity']['state'] == 'STARTED'
    end

    # Determine the endpoint the app will be listening on for requests.
    route_mappings = JSON.load capture("cf curl '/v2/apps/#{app_guid}/route_mappings'")
    run "echo '#{route_mappings.to_json}' | jq -C ."
    STDOUT.flush

    route_url = route_mappings['resources'].map{ |resource| resource['entity']['route_url'] }.reject(&:nil?).reject(&:empty?).first
    puts "# Route URL: #{route_url}"
    STDOUT.flush

    route_info = JSON.load capture("cf curl #{route_url}")
    run "echo '#{route_info.to_json}' | jq -C ."
    STDOUT.flush

    app_host = route_info['entity']['host']
    domain_url = route_info['entity']['domain_url']
    domain_info = JSON.load capture("cf curl #{domain_url}")
    run "echo '#{domain_info.to_json}' | jq -C ."
    STDOUT.flush

    app_domain = domain_info['entity']['name']
    app_url = "http://#{app_host}.#{app_domain}"

    # Check with the app at its endpoint that it is able to use the
    # service it was bound to.
    run "curl -L -v --fail #{app_url}/"
    run "curl -L -v --fail -X POST #{app_url}/todos --data text='hello'"
    run "curl -L #{app_url}/todos"
    todos = JSON.load capture("curl -L #{app_url}/todos")
    run "echo '#{todos.to_json}' | jq -C ."
    todo_id = todos.first['id']
    run "curl -L -v --fail #{app_url}/todos/#{todo_id}"
    run "curl -L -v --fail -X DELETE #{app_url}/todos/#{todo_id}"
end
