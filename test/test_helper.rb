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

# Rails gives uuid fixtures name-based (v5) ids that sort arbitrarily against the
# uuidv7 ids created rows get, breaking `Model.last`/`order(:id)` in tests. Force
# fixture ids into a fixed, always-earlier range so fixtures precede created rows.
module OrderableUuidFixtures
  def identify(label, column_type = :integer)
    return super unless column_type == :uuid

    "00000000-0000-7000-8000-#{Digest::MD5.hexdigest(label.to_s)[0, 12]}"
  end
end
ActiveRecord::FixtureSet.singleton_class.prepend(OrderableUuidFixtures)

require "webmock/minitest"
require "minitest/mock"
require "super_diff"

# Load support modules in deterministic order
Dir[Rails.root.join("test/support/**/*.rb")].sort.each { |f| require f }

# Drive the real RateLimit limiter in tests instead of stubbing acquire, so the
# job specs exercise actual token-bucket behaviour. Use inside freeze_time so
# nothing refills mid-setup, and travel/travel_to to let it refill.
module RateLimitTestHelper
  # Spend real tokens so the FreeFeed subject's bucket holds exactly `remaining`
  # for `dimension`.
  def drain_freefeed(subject, dimension, remaining: 0)
    capacity = RateLimit.capacity(:freefeed, dimension)
    (capacity - remaining).times do
      RateLimit.acquire(:freefeed, subject: subject, cost: { dimension => 1 })
    end
  end

  # How many `dimension` tokens the subject has left, measured by spending them.
  # Consumes the remainder, so call it only at the end of a test.
  def freefeed_tokens_left(subject, dimension)
    capacity = RateLimit.capacity(:freefeed, dimension)
    (1..capacity).count { RateLimit.acquire(:freefeed, subject: subject, cost: { dimension => 1 }).allowed? }
  end
end

module ActiveSupport
  class TestCase
    include FactoryBot::Syntax::Methods
    include SnapshotTesting
    include RateLimitTestHelper

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
