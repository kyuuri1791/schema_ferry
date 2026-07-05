# frozen_string_literal: true

require "schema_ferry"
require "support/fixtures"

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include Fixtures
end
