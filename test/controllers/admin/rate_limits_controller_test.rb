require "test_helper"

class Admin::RateLimitsControllerTest < ActionDispatch::IntegrationTest
  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "should redirect non-dev users" do
    sign_in_as(regular_user)

    get admin_rate_limits_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users" do
    get admin_rate_limits_path

    assert_redirected_to new_session_path
  end

  test "should render the empty state when no buckets exist" do
    sign_in_as(dev_user)

    get admin_rate_limits_path

    assert_response :success
    assert_select "[data-key='empty-state']"
  end

  test "should show headroom for an active subject" do
    RateLimit.acquire(:freefeed, subject: "freefeed:7", cost: { post: 10 })
    sign_in_as(dev_user)

    get admin_rate_limits_path

    assert_response :success
    assert_select "[data-key='rate-limit.policy.freefeed']"
    assert_select "[data-subject='freefeed:7']"
    assert_select "[data-key='rate-limit.bucket'][data-dimension='post']"
  end

  test "should surface a cooldown badge when a subject is blocked" do
    RateLimit.acquire(:freefeed, subject: "freefeed:7", cost: { post: 1 })
    RateLimit.penalize(:freefeed, subject: "freefeed:7", retry_after: 45)
    sign_in_as(dev_user)

    get admin_rate_limits_path

    assert_response :success
    assert_select "[data-key='rate-limit.cooldown']", text: /Cooling down/
  end
end
