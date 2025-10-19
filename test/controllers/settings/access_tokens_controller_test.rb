require "test_helper"

class Settings::AccessTokensControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  test "requires authentication for index" do
    get settings_access_tokens_path
    assert_redirected_to new_session_path
  end

  test "shows access tokens index when authenticated" do
    sign_in_as user
    get settings_access_tokens_path
    assert_response :success
    assert_select "h1", "Access Tokens"
  end

  test "displays empty state when no tokens" do
    sign_in_as user
    get settings_access_tokens_path
    assert_response :success
    assert_select "h5", "No access tokens yet"
    assert_select "p", text: /Add Freefeed API access token/
  end

  test "displays existing tokens" do
    sign_in_as user
    access_token
    get settings_access_tokens_path
    assert_response :success
    assert_select "table"
    assert_select "td", access_token.name
  end

  test "creates access token with valid params" do
    sign_in_as user
    assert_difference "user.access_tokens.count", 1 do
      post settings_access_tokens_path, params: { access_token: { name: "Test Token", token: "freefeed_token_123" } }
    end
    assert_redirected_to settings_access_tokens_path
    assert_match /created successfully/, flash[:notice]
  end

  test "requires authentication for new" do
    get new_settings_access_token_path
    assert_redirected_to new_session_path
  end

  test "shows new token form when authenticated" do
    sign_in_as user
    get new_settings_access_token_path
    assert_response :success
    assert_select "h1", "Create New Token"
    assert_select "form[action=?]", settings_access_tokens_path
  end

  test "shows validation errors for invalid params" do
    sign_in_as user
    post settings_access_tokens_path, params: { access_token: { name: "", token: "freefeed_token_123" } }
    assert_response :unprocessable_content
    assert_select ".alert-danger"
    assert_select "h1", "Create New Token"
  end

  test "shows validation errors for missing token" do
    sign_in_as user
    post settings_access_tokens_path, params: { access_token: { name: "Test Token", token: "" } }
    assert_response :unprocessable_content
    assert_select ".alert-danger"
    assert_select "h1", "Create New Token"
  end

  test "prevents duplicate names for same user" do
    sign_in_as user
    create(:access_token, name: "Duplicate", user: user)
    post settings_access_tokens_path, params: { access_token: { name: "Duplicate", token: "freefeed_token_123" } }
    assert_response :unprocessable_content
    assert_select "h1", "Create New Token"
  end

  test "allows duplicate names for different users" do
    user1 = create(:user)
    user2 = create(:user)
    create(:access_token, name: "Same Name", user: user1)

    sign_in_as user2
    assert_difference "user2.access_tokens.count", 1 do
      post settings_access_tokens_path, params: { access_token: { name: "Same Name", token: "freefeed_token_456" } }
    end
    assert_redirected_to settings_access_tokens_path
  end

  test "deletes access token" do
    sign_in_as user
    token_id = access_token.id
    assert_difference "user.access_tokens.count", -1 do
      delete settings_access_token_path(access_token)
    end
    assert_not AccessToken.exists?(token_id)
    assert_redirected_to settings_access_tokens_path
    assert_match /deleted/, flash[:notice]
  end

  test "cannot delete other user's token" do
    other_user = create(:user)
    other_token = create(:access_token, user: other_user)

    sign_in_as user
    delete settings_access_token_path(other_token)
    assert_response :not_found
  end

  test "requires authentication for create" do
    post settings_access_tokens_path, params: { access_token: { name: "Test", token: "freefeed_token_123" } }
    assert_redirected_to new_session_path
  end

  test "requires authentication for destroy" do
    delete settings_access_token_path(access_token)
    assert_redirected_to new_session_path
  end

  test "shows edit form for token replacement" do
    sign_in_as user
    get edit_settings_access_token_path(access_token)
    assert_response :success
    assert_select "h1", "Edit Token"
    assert_select "form[action=?]", settings_access_token_path(access_token)
    assert_select "input[name=?][value='']", "access_token[token]" # Token field should be empty
    assert_select "input[name=?][value=?]", "access_token[name]", access_token.name
  end

  test "updates access token successfully" do
    sign_in_as user

    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(headers: { "Authorization" => "Bearer new_token_123" })
      .to_return(status: 200, body: { users: { username: "testuser" } }.to_json)

    assert_enqueued_with(job: TokenValidationJob) do
      patch settings_access_token_path(access_token), params: {
        access_token: { name: "Updated Token", token: "new_token_123", host: access_token.host }
      }
    end

    assert_redirected_to settings_access_tokens_path
    assert_match /updated successfully/, flash[:notice]

    access_token.reload
    assert_equal "Updated Token", access_token.name
    assert_equal "new_token_123", access_token.token_value
  end

  test "handles update validation errors" do
    sign_in_as user
    patch settings_access_token_path(access_token), params: {
      access_token: { name: "", token: "new_token_123" }
    }
    assert_response :unprocessable_content
    assert_select "h1", "Edit Token"
    assert_select ".alert-danger"
  end

  test "updates only name without changing token" do
    sign_in_as user
    original_token = access_token.token_value

    assert_no_enqueued_jobs(only: TokenValidationJob) do
      patch settings_access_token_path(access_token), params: {
        access_token: { name: "New Name", token: "", host: access_token.host }
      }
    end

    assert_redirected_to settings_access_tokens_path
    assert_match /updated successfully/, flash[:notice]

    access_token.reload
    assert_equal "New Name", access_token.name
    assert_equal original_token, access_token.token_value
  end

  test "updates only host without changing token" do
    sign_in_as user
    original_token = access_token.token_value
    original_name = access_token.name
    new_host = AccessToken::FREEFEED_HOSTS["staging"][:url]

    assert_no_enqueued_jobs(only: TokenValidationJob) do
      patch settings_access_token_path(access_token), params: {
        access_token: { name: original_name, token: "", host: new_host }
      }
    end

    assert_redirected_to settings_access_tokens_path
    assert_match /updated successfully/, flash[:notice]

    access_token.reload
    assert_equal original_name, access_token.name
    assert_equal new_host, access_token.host
    assert_equal original_token, access_token.token_value
  end

  test "cannot edit other user's token" do
    other_user = create(:user)
    other_token = create(:access_token, user: other_user)

    sign_in_as user
    get edit_settings_access_token_path(other_token)
    assert_response :not_found
  end

  test "cannot update other user's token" do
    other_user = create(:user)
    other_token = create(:access_token, user: other_user)

    sign_in_as user
    patch settings_access_token_path(other_token), params: {
      access_token: { name: "Hacked", token: "evil_token" }
    }
    assert_response :not_found
  end

  test "requires authentication for edit" do
    get edit_settings_access_token_path(access_token)
    assert_redirected_to new_session_path
  end

  test "requires authentication for update" do
    patch settings_access_token_path(access_token), params: {
      access_token: { name: "Updated", token: "new_token" }
    }
    assert_redirected_to new_session_path
  end
end
