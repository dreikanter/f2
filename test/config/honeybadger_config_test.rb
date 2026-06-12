require "test_helper"

# Verifies config/initializers/honeybadger.rb.
class HoneybadgerConfigTest < ActiveSupport::TestCase
  test "ignores RateLimit::Throttled since RateLimited handles it by rescheduling" do
    assert_includes Honeybadger.config.ignored_classes, "RateLimit::Throttled"
  end
end
