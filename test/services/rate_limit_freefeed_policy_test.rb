require "test_helper"

# Verifies the :freefeed policy registered by config/initializers/rate_limits.rb.
class RateLimitFreefeedPolicyTest < ActiveSupport::TestCase
  test "the :freefeed policy limits posts under FreeFeed's POST ceiling" do
    limit = RateLimit.policy(:freefeed).buckets_for(post: 1).map(&:first).sole

    assert_equal 50, limit.rate
    assert_equal 60, limit.window
  end

  test "the :freefeed policy fails open" do
    assert RateLimit.policy(:freefeed).fail_open?
  end
end
