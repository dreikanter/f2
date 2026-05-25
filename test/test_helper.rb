ENV["RAILS_ENV"] ||= "test"

require "simplecov"
require "simplecov-cobertura"

SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::CoberturaFormatter
]

SimpleCov.start "rails"

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "minitest/mock"
require "super_diff"

# Load support modules in deterministic order
Dir[Rails.root.join("test/support/**/*.rb")].sort.each { |f| require f }

module ActiveSupport
  class TestCase
    include FactoryBot::Syntax::Methods
    include SnapshotTesting

    # Run tests in parallel with specified workers
    # Disable parallel testing when SimpleCov is running to get accurate coverage
    parallelize(workers: ENV["COVERAGE"] ? 1 : :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

module ActionDispatch
  class IntegrationTest
    include IntegrationTestHelpers
  end
end
