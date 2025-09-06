require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "requires authentication" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "shows dashboard when authenticated" do
    sign_in_as user
    get root_path
    assert_response :success
    assert_select "h1", "Dashboard"
  end

  test "shows API access info box when user has no tokens" do
    sign_in_as user
    get root_path
    assert_select ".card-title", "API Access"
    assert_select "p", text: /haven't created any access tokens yet/
    assert_select "a[href='#{access_tokens_path}']", "Create your first access token"
  end

  test "shows token count when user has tokens" do
    sign_in_as user
    create(:access_token, user: user)
    create(:access_token, user: user)

    get root_path
    assert_select ".font-weight-bold", "2"
    assert_select ".text-muted", "Active Tokens"
  end

  test "shows singular token text for one token" do
    sign_in_as user
    create(:access_token, user: user)

    get root_path
    assert_select ".font-weight-bold", "1"
    assert_select ".text-muted", "Active Token"
  end

  test "does not count inactive tokens" do
    sign_in_as user
    create(:access_token, user: user)
    create(:access_token, :inactive, user: user)

    get root_path
    assert_select ".font-weight-bold", "1"
  end
end
