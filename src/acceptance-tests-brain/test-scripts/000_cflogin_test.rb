#!/usr/bin/env ruby

exit_skipping_test if ENV['CFLOGIN_ENABLED'] != 'true'

require_relative 'testutils'

login
setup_org_space
