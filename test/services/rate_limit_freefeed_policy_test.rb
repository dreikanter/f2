require "test_helper"

# Verifies the :freefeed policy registered by config/initializers/rate_limits.rb.
#
# FreeFeed meters each method over a *rolling* one-minute window, so the most a
# token bucket can spend in any single window is burst + rate (a full bucket
# plus a minute of refill). Every dimension must keep that sum under FreeFeed's
# ceiling, or bursts get the whole account blocked server-side.
class RateLimitFreefeedPolicyTest < ActiveSupport::TestCase
  FREEFEED_CEILINGS = { post: 60, get: 200, delete: 30 }.freeze

  test "the :freefeed policy limits posts under FreeFeed's POST ceiling" do
    limit = limit_for(:post)

    assert_equal 30, limit.rate
    assert_equal 20, limit.burst
    assert_equal 60, limit.window
  end

  test "the :freefeed policy limits gets under FreeFeed's GET ceiling" do
    limit = limit_for(:get)

    assert_equal 100, limit.rate
    assert_equal 30, limit.burst
    assert_equal 60, limit.window
  end

  test "the :freefeed policy limits deletes under FreeFeed's fallback ceiling" do
    limit = limit_for(:delete)

    assert_equal 15, limit.rate
    assert_equal 10, limit.burst
    assert_equal 60, limit.window
  end

  test "worst-case rolling-minute spend stays under FreeFeed's ceiling for every dimension" do
    FREEFEED_CEILINGS.each do |dimension, ceiling|
      limit = limit_for(dimension)

      assert_operator limit.burst + limit.rate, :<, ceiling,
        "#{dimension}: burst #{limit.burst} + rate #{limit.rate} must stay under FreeFeed's #{ceiling}/min"
    end
  end

  test "the :freefeed policy fails open" do
    assert RateLimit.policy(:freefeed).fail_open?
  end

  private

  def limit_for(dimension)
    RateLimit.policy(:freefeed).buckets_for(dimension => 1).map(&:first).sole
  end
end
