require "test_helper"

class Admin::AccessTokensControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= begin
      user = create(:user)
      create(:permission, user: user, name: "admin")
      user
    end
  end

  def access_token
    @access_token ||= create(:access_token, :active)
  end

  test "#show should redirect non-admin users" do
    sign_in_as(create(:user))

    get admin_access_token_path(access_token)

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#show should redirect unauthenticated users" do
    get admin_access_token_path(access_token)

    assert_redirected_to new_session_path
  end

  test "#show should display another user's token with an owner link" do
    sign_in_as(admin_user)

    get admin_access_token_path(access_token)

    assert_response :success
    assert_select "h1", access_token.name
    assert_select "a[href=?]", admin_user_path(access_token.user), text: access_token.user.email_address
    assert_select "a[href=?]", admin_path, text: "Admin Panel"
    assert_select "[data-key='token.freefeed_user']"
  end

  test "#show should not expose the token value or management actions" do
    sign_in_as(admin_user)
    feed = create(:feed, user: access_token.user, access_token: access_token)

    get admin_access_token_path(access_token)

    assert_response :success
    assert_no_match access_token.token, response.body
    assert_select "a[href=?]", edit_access_token_path(access_token), count: 0
    assert_no_match "Delete…", response.body
    assert_select "[data-key='admin.access_token.show'] a[href=?]", access_tokens_path, count: 0
    assert_select "a[href=?]", admin_feed_path(feed)
  end
end
