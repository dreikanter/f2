require "test_helper"

class OnboardingsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user, :with_onboarding)
  end

  test "should show onboarding page when authenticated and onboarding exists" do
    sign_in_as(user)
    get onboarding_url
    assert_response :success
  end

  test "should redirect to status when onboarding does not exist" do
    user_without_onboarding = create(:user)
    sign_in_as(user_without_onboarding)

    get onboarding_url
    assert_redirected_to status_path
  end

  test "should clear session flag when onboarding does not exist" do
    user_without_onboarding = create(:user)

    open_session do |s|
      s.sign_in_as(user_without_onboarding)
      s.session[:onboarding] = true

      s.get onboarding_url
      assert_equal false, s.session[:onboarding]
    end
  end

  test "should destroy onboarding" do
    sign_in_as(user)
    assert_not_nil user.onboarding

    delete onboarding_url
    assert_nil user.reload.onboarding
    assert_redirected_to status_path
  end

  test "should clear session flag when destroying onboarding" do
    open_session do |s|
      s.sign_in_as(user)
      s.session[:onboarding] = true

      s.delete onboarding_url
      assert_equal false, s.session[:onboarding]
    end
  end

  test "should handle destroy when onboarding does not exist" do
    user_without_onboarding = create(:user)
    sign_in_as(user_without_onboarding)

    delete onboarding_url
    assert_redirected_to status_path
  end

  test "should require authentication to access onboarding" do
    get onboarding_url
    assert_redirected_to new_session_path
  end

  test "should require authentication to create onboarding" do
    post onboarding_url
    assert_redirected_to new_session_path
  end

  test "should require authentication to destroy onboarding" do
    delete onboarding_url
    assert_redirected_to new_session_path
  end

  test "should create onboarding when it does not exist" do
    user_without_onboarding = create(:user)
    sign_in_as(user_without_onboarding)

    assert_nil user_without_onboarding.onboarding

    post onboarding_url
    assert_not_nil user_without_onboarding.reload.onboarding
    assert_redirected_to onboarding_path
  end

  test "should set session flag when creating onboarding" do
    user_without_onboarding = create(:user)
    sign_in_as(user_without_onboarding)

    post onboarding_url
    assert_equal true, session[:onboarding]
  end

  test "should find existing onboarding instead of creating duplicate" do
    sign_in_as(user)
    existing_onboarding_id = user.onboarding.id

    post onboarding_url
    assert_equal existing_onboarding_id, user.reload.onboarding.id
  end

  test "should reset access_token and feed when restarting onboarding" do
    user_with_both = create(:user)
    access_token = create(:access_token, user: user_with_both)
    feed = create(:feed, user: user_with_both)
    onboarding = create(:onboarding, user: user_with_both, access_token: access_token, feed: feed)
    sign_in_as(user_with_both)

    post onboarding_url
    onboarding.reload

    assert_nil onboarding.access_token_id
    assert_nil onboarding.feed_id
  end

  test "should show intro step when no access_token" do
    sign_in_as(user)
    get onboarding_url
    assert_response :success
    assert_select "h1", "Welcome to Feeder"
  end

  test "should show feed step when access_token exists but no feed" do
    user_with_token = create(:user)
    access_token = create(:access_token, user: user_with_token)
    onboarding = create(:onboarding, user: user_with_token, access_token: access_token)
    sign_in_as(user_with_token)

    get onboarding_url
    assert_response :success
    assert_select "h1", "Token added"
  end

  test "should show outro step when both access_token and feed exist" do
    user_with_both = create(:user)
    access_token = create(:access_token, user: user_with_both)
    feed = create(:feed, user: user_with_both)
    onboarding = create(:onboarding, user: user_with_both, access_token: access_token, feed: feed)
    sign_in_as(user_with_both)

    get onboarding_url
    assert_response :success
    assert_select "h1", "You're all set"
  end

  test "should override step with step parameter 1" do
    user_with_both = create(:user)
    access_token = create(:access_token, user: user_with_both)
    feed = create(:feed, user: user_with_both)
    onboarding = create(:onboarding, user: user_with_both, access_token: access_token, feed: feed)
    sign_in_as(user_with_both)

    get onboarding_url(step: 1)
    assert_response :success
    assert_select "h1", "Welcome to Feeder"
  end

  test "should override step with step parameter 2" do
    sign_in_as(user)
    get onboarding_url(step: 2)
    assert_response :success
    assert_select "h1", "Token added"
  end

  test "should override step with step parameter 3" do
    sign_in_as(user)
    get onboarding_url(step: 3)
    assert_response :success
    assert_select "h1", "You're all set"
  end
end
