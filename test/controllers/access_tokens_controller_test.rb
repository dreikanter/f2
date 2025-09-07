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
    assert_select "p", text: /Add Freefeed API access token/
  end

  test "displays existing tokens" do
    sign_in_as user
    access_token
    get access_tokens_path
    assert_select "table"
    assert_select "td", access_token.name
  end

  test "creates access token with valid params" do
    sign_in_as user
    assert_difference "user.access_tokens.count", 1 do
      post access_tokens_path, params: { access_token: { name: "Test Token", token: "freefeed_token_123" } }
    end
    assert_redirected_to access_tokens_path
    assert_match /created successfully/, flash[:notice]
  end

  test "requires authentication for new" do
    get new_access_token_path
    assert_redirected_to new_session_path
  end

  test "shows new token form when authenticated" do
    sign_in_as user
    get new_access_token_path
    assert_response :success
    assert_select "h1", "Create New Token"
    assert_select "form[action=?]", access_tokens_path
  end

  test "shows validation errors for invalid params" do
    sign_in_as user
    post access_tokens_path, params: { access_token: { name: "", token: "freefeed_token_123" } }
    assert_response :unprocessable_content
    assert_select ".alert-danger"
    assert_select "h1", "Create New Token"
  end

  test "shows validation errors for missing token" do
    sign_in_as user
    post access_tokens_path, params: { access_token: { name: "Test Token", token: "" } }
    assert_response :unprocessable_content
    assert_select ".alert-danger"
    assert_select "h1", "Create New Token"
  end

  test "prevents duplicate names for same user" do
    sign_in_as user
    create(:access_token, name: "Duplicate", user: user)
    post access_tokens_path, params: { access_token: { name: "Duplicate", token: "freefeed_token_123" } }
    assert_response :unprocessable_content
    assert_select "h1", "Create New Token"
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

  test "deletes access token" do
    sign_in_as user
    token_id = access_token.id
    assert_difference "user.access_tokens.count", -1 do
      delete access_token_path(access_token)
    end
    assert_not AccessToken.exists?(token_id)
    assert_redirected_to access_tokens_path
    assert_match /deleted/, flash[:notice]
  end

  test "cannot delete other user's token" do
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
