#!/usr/bin/env ruby

require_relative 'testutils'

exit_skipping_test if ENV['CFLOGIN_ENABLED'] != 'true'

login
setup_org_space
