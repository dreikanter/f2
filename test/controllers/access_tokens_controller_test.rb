require "test_helper"

class AccessTokensControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  test "#index should require authentication" do
    get access_tokens_path
    assert_redirected_to new_session_path
  end

  test "#index should show access tokens list" do
    sign_in_as user
    get access_tokens_path

    assert_response :success
    assert_select "h1", "Freefeed Access Tokens"
    assert_select "nav[aria-label='Breadcrumb'] a[href=?]", settings_path, text: "Settings"
  end

  test "#index should display empty state" do
    sign_in_as user
    get access_tokens_path

    assert_response :success
    assert_select "[data-key='empty-state']", text: /No FreeFeed access tokens yet/
  end

  test "#index should display existing tokens" do
    sign_in_as user
    access_token
    get access_tokens_path

    assert_response :success
    assert_select "[data-key='settings.access_tokens.#{access_token.id}']"
  end

  test "#index should display host when token owner is not set" do
    sign_in_as user
    token = create(:access_token, user: user, owner: nil)
    get access_tokens_path

    assert_response :success
    assert_match(token.host_domain, response.body)
  end

  test "#show should redirect to sign in form" do
    get access_token_path(access_token)
    assert_redirected_to new_session_path
  end

  test "#show should render for own token" do
    sign_in_as user
    get access_token_path(access_token)

    assert_response :success
    assert_select "h1", access_token.name
  end

  test "#show should not render for other user's token" do
    other_token = create(:access_token, user: create(:user))
    sign_in_as user
    get access_token_path(other_token)

    assert_response :not_found
  end

  test "#new should render when authenticated" do
    sign_in_as user
    get new_access_token_path

    assert_response :success
  end

  test "#create should redirect to show page on success" do
    sign_in_as user

    assert_difference("AccessToken.count", 1) do
      post access_tokens_path, params: {
        access_token: {
          name: "Test Token",
          token: "test_token_123",
          host: AccessToken::FREEFEED_HOSTS[:production][:url]
        }
      }
    end

    assert_redirected_to access_token_path(AccessToken.last)
  end


  test "#new should accept and remember a feed_id owned by current_user" do
    sign_in_as user
    draft = create(:feed, :draft, user: user)

    get new_access_token_path, params: { feed_id: draft.id }

    assert_response :success
    assert_select "h1", "New Access Token"
  end

  test "#new should ignore foreign feed_id" do
    sign_in_as user
    other_draft = create(:feed, :draft, user: create(:user))

    get new_access_token_path, params: { feed_id: other_draft.id }

    assert_response :success
    assert_select "h1", "New Access Token"
  end

  test "#create should auto-attach the token to the owned feed" do
    sign_in_as user
    draft = create(:feed, :without_access_token, :draft, user: user)

    post access_tokens_path, params: {
      feed_id: draft.id,
      access_token: {
        name: "Test Token",
        token: "test_token_123",
        host: AccessToken::FREEFEED_HOSTS[:production][:url]
      }
    }

    assert_equal AccessToken.last.id, draft.reload.access_token_id
  end

  test "#create should not attach when feed_id is foreign" do
    sign_in_as user
    other_draft = create(:feed, :without_access_token, :draft, user: create(:user))

    post access_tokens_path, params: {
      feed_id: other_draft.id,
      access_token: {
        name: "Test Token",
        token: "test_token_123",
        host: AccessToken::FREEFEED_HOSTS[:production][:url]
      }
    }

    assert_nil other_draft.reload.access_token_id
  end

  test "#create should redirect with feed_id in the show path" do
    sign_in_as user
    draft = create(:feed, :without_access_token, :draft, user: user)

    post access_tokens_path, params: {
      feed_id: draft.id,
      access_token: {
        name: "Test Token",
        token: "test_token_123",
        host: AccessToken::FREEFEED_HOSTS[:production][:url]
      }
    }

    assert_redirected_to access_token_path(AccessToken.last, feed_id: draft.id)
  end

  test "#show should render Continue setting up your feed link when token is active and feed_id is owned" do
    sign_in_as user
    active = create(:access_token, :active, user: user)
    draft = create(:feed, :draft, user: user)

    get access_token_path(active, feed_id: draft.id)

    assert_response :success
    assert_select "a[href=?]", edit_feed_path(draft.id), text: "Continue setting up your feed"
  end

  test "#show should not render Continue setting up your feed link when token is pending" do
    sign_in_as user
    pending = create(:access_token, user: user, status: :pending)
    draft = create(:feed, :draft, user: user)

    get access_token_path(pending, feed_id: draft.id)

    assert_response :success
    assert_select "a", text: "Continue setting up your feed", count: 0
  end

  test "#show should render Back to your feed link in all states when feed_id is present" do
    sign_in_as user
    draft = create(:feed, :draft, user: user)

    [create(:access_token, user: user, status: :pending),
     create(:access_token, :active, user: user),
     create(:access_token, :inactive, user: user)].each do |token|
      get access_token_path(token, feed_id: draft.id)
      assert_select "a[href=?]", edit_feed_path(draft.id), text: "Back to your feed"
    end
  end

  test "#show should not render Back to your feed link when feed_id is missing" do
    sign_in_as user
    active = create(:access_token, :active, user: user)

    get access_token_path(active)

    assert_select "a", text: "Back to your feed", count: 0
  end

  test "#new should point Cancel to feed editor when feed_id is present" do
    sign_in_as user
    draft = create(:feed, :draft, user: user)

    get new_access_token_path, params: { feed_id: draft.id }

    assert_select "a[href=?]", edit_feed_path(draft), text: "Cancel"
  end

  test "#new should point Cancel to tokens list when feed_id is absent" do
    sign_in_as user

    get new_access_token_path

    assert_select "a[href=?]", access_tokens_path, text: "Cancel"
  end

  test "#show should not render Continue setting up your feed link when feed_id is missing" do
    sign_in_as user
    active = create(:access_token, :active, user: user)

    get access_token_path(active)

    assert_response :success
    assert_select "a", text: "Continue setting up your feed", count: 0
  end

  test "#create should render new form on validation error" do
    sign_in_as user

    assert_no_difference("AccessToken.count") do
      post access_tokens_path, params: {
        access_token: {
          name: "Test Token",
          token: "", # Invalid: empty token
          host: AccessToken::FREEFEED_HOSTS[:production][:url]
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "New Access Token"
  end

  test "#create should reject unknown host" do
    sign_in_as user

    assert_no_difference("AccessToken.count") do
      post access_tokens_path, params: {
        access_token: {
          name: "Test Token",
          token: "test_token_123",
          host: "https://unknown.example.com"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "New Access Token"
  end

  test "#create should require authentication" do
    assert_no_difference("AccessToken.count") do
      post access_tokens_path, params: {
        access_token: {
          name: "Test Token",
          token: "test_token_123",
          host: AccessToken::FREEFEED_HOSTS[:production][:url]
        }
      }
    end

    assert_redirected_to new_session_path
  end

  test "#edit should require authentication" do
    get edit_access_token_path(access_token)
    assert_redirected_to new_session_path
  end

  test "#edit should render for own token" do
    sign_in_as user
    get edit_access_token_path(access_token)

    assert_response :success
    assert_select "h1", "Edit Access Token"
  end

  test "#edit should not render for other user's token" do
    other_token = create(:access_token, user: create(:user))
    sign_in_as user
    get edit_access_token_path(other_token)

    assert_response :not_found
  end

  test "#update should require authentication" do
    patch access_token_path(access_token), params: { access_token: { name: "New Name" } }
    assert_redirected_to new_session_path
  end

  test "#update should update name" do
    sign_in_as user
    patch access_token_path(access_token), params: { access_token: { name: "Updated Name" } }

    assert_redirected_to access_token_path(access_token)
    assert_equal "Updated Name", access_token.reload.name
    assert_equal "Changes saved.", flash[:success]
  end

  test "#update should not re-validate when only name changes" do
    sign_in_as user
    assert_no_enqueued_jobs do
      patch access_token_path(access_token), params: { access_token: { name: "Updated Name" } }
    end
  end

  test "#update should update encrypted token and re-validate when new token provided" do
    sign_in_as user
    assert_enqueued_jobs 1, only: TokenValidationJob do
      patch access_token_path(access_token), params: {
        access_token: { name: access_token.name, token: "new_token_value" }
      }
    end

    assert_redirected_to access_token_path(access_token)
  end

  test "#update should render edit on validation error" do
    sign_in_as user
    other = create(:access_token, name: "Taken Name", user: user)
    patch access_token_path(access_token), params: { access_token: { name: other.name } }

    assert_response :unprocessable_entity
    assert_select "h1", "Edit Access Token"
  end

  test "#update should not update other user's token" do
    other_token = create(:access_token, user: create(:user))
    sign_in_as user
    patch access_token_path(other_token), params: { access_token: { name: "Hacked" } }

    assert_response :not_found
  end

  test "requires authentication for destroy" do
    delete access_token_path(access_token)

    assert_redirected_to new_session_path
  end

  test "deletes access token" do
    sign_in_as user
    access_token

    assert_difference("AccessToken.count", -1) do
      delete access_token_path(access_token)
    end

    assert_redirected_to access_tokens_path
    assert_equal "Access token '#{access_token.name}' deleted.", flash[:success]
  end

  test "cannot delete other user's token" do
    other_token = create(:access_token, user: create(:user))
    sign_in_as user

    assert_no_difference("AccessToken.count") do
      delete access_token_path(other_token)
    end

    assert_response :not_found
  end
end
