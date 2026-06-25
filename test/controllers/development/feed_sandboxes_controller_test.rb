require "test_helper"

class Development::FeedSandboxesControllerTest < ActionDispatch::IntegrationTest
  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "#show should require authentication" do
    get development_feed_sandbox_path

    assert_response :redirect
  end

  test "#show should require dev permission" do
    sign_in_as(regular_user)
    get development_feed_sandbox_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#show should render the chooser previews" do
    sign_in_as(dev_user)
    get development_feed_sandbox_path

    assert_response :success
    assert_select "h1", "Feed Sandbox"
    assert_select '[data-key="chooser-example.0"]'
    assert_select '[data-key="candidates"]', minimum: 2
  end

  test "#show should list every mock source state with a copyable link" do
    sign_in_as(dev_user)
    get development_feed_sandbox_path

    assert_response :success
    Development::SampleFeedsController::STATES.each_key do |state|
      assert_select %([data-key="sample-state.#{state}"])
      assert_select %([data-key="sample-state.#{state}.copy"])
    end
  end
end
