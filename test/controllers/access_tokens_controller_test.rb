require "test_helper"

class AccessTokensControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  test "requires authentication for index" do
    get access_tokens_path
    assert_redirected_to new_session_path
  end

  test "shows access tokens index when authenticated" do
    sign_in_as user
    get access_tokens_path
    assert_response :success
    assert_select "h1", "Access Tokens"
  end

  test "displays empty state when no tokens" do
    sign_in_as user
    get access_tokens_path
    assert_select "h5", "No access tokens yet"
    assert_select "p", text: /Create your first access token/
  end

  test "displays existing tokens" do
    sign_in_as user
    access_token
    get access_tokens_path
    assert_select "table"
    assert_select "code", access_token.name
  end

  test "creates access token with valid params" do
    sign_in_as user
    assert_difference "user.access_tokens.count", 1 do
      post access_tokens_path, params: { access_token: { name: "Test Token", token: "freefeed_token_123" } }
    end
    assert_redirected_to access_tokens_path
    assert_match /created successfully/, flash[:notice]
  end

  test "shows validation errors for invalid params" do
    sign_in_as user
    post access_tokens_path, params: { access_token: { name: "", token: "freefeed_token_123" } }
    assert_response :unprocessable_content
    assert_select ".alert-danger"
  end

  test "shows validation errors for missing token" do
    sign_in_as user
    post access_tokens_path, params: { access_token: { name: "Test Token", token: "" } }
    assert_response :unprocessable_content
    assert_select ".alert-danger"
  end

  test "prevents duplicate names for same user" do
    sign_in_as user
    create(:access_token, name: "Duplicate", user: user)
    post access_tokens_path, params: { access_token: { name: "Duplicate", token: "freefeed_token_123" } }
    assert_response :unprocessable_content
  end

  test "allows duplicate names for different users" do
    user1 = create(:user)
    user2 = create(:user)
    create(:access_token, name: "Same Name", user: user1)

    sign_in_as user2
    assert_difference "user2.access_tokens.count", 1 do
      post access_tokens_path, params: { access_token: { name: "Same Name", token: "freefeed_token_456" } }
    end
    assert_redirected_to access_tokens_path
  end

  test "deactivates access token" do
    sign_in_as user
    assert access_token.active?
    delete access_token_path(access_token)
    assert_not access_token.reload.active?
    assert_redirected_to access_tokens_path
    assert_match /deactivated/, flash[:notice]
  end

  test "cannot deactivate other user's token" do
    other_user = create(:user)
    other_token = create(:access_token, user: other_user)

    sign_in_as user
    delete access_token_path(other_token)
    assert_response :not_found
  end

  test "requires authentication for create" do
    post access_tokens_path, params: { access_token: { name: "Test", token: "freefeed_token_123" } }
    assert_redirected_to new_session_path
  end

  test "requires authentication for destroy" do
    delete access_token_path(access_token)
    assert_redirected_to new_session_path
  end
end
