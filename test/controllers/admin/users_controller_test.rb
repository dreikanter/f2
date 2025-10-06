require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "should redirect non-admin users from index" do
    login_as(regular_user)

    get admin_users_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users from index" do
    get admin_users_path

    assert_redirected_to new_session_path
  end

  test "should allow admin users to view users index" do
    login_as(admin_user)
    other_user = create(:user, email_address: "other@example.com")

    get admin_users_path

    assert_response :success
    assert_select "h1", "Users"
    assert_select "a[href='#{admin_user_path(other_user)}']", text: "other@example.com"
  end

  test "should allow admin users to view user details" do
    login_as(admin_user)
    user = create(:user, email_address: "test@example.com")

    get admin_user_path(user)

    assert_response :success
    assert_select "h1", "test@example.com"
  end

  test "should redirect non-admin users from show" do
    login_as(regular_user)
    user = create(:user)

    get admin_user_path(user)

    assert_redirected_to root_path
  end

  test "should paginate users" do
    login_as(admin_user)

    30.times do |i|
      create(:user, email_address: "user#{i}_#{rand(10000)}@example.com")
    end

    get admin_users_path

    assert_response :success
    assert_select ".pagination"
    assert_select "tbody tr", count: 25
  end

  test "should display user statistics on show page" do
    login_as(admin_user)
    user = create(:user)
    feed1 = create(:feed, user: user, state: :enabled)
    feed2 = create(:feed, user: user, state: :disabled)
    token1 = create(:access_token, user: user, status: "active")
    token2 = create(:access_token, user: user, status: "inactive")
    post1 = create(:post, feed: feed1)

    get admin_user_path(user)

    assert_response :success
    assert_select "strong", text: "Feeds:"
    assert_select "strong", text: "Access Tokens:"
    assert_select "strong", text: "Posts:"
  end

  test "should show permissions on user details" do
    login_as(admin_user)
    regular = create(:user)

    get admin_user_path(admin_user)
    assert_response :success
    assert_select "strong", text: "Permissions:"

    get admin_user_path(regular)
    assert_response :success
    assert_select "strong", text: "Permissions:"
  end

  test "should show password updated timestamp" do
    login_as(admin_user)
    user = create(:user)

    get admin_user_path(user)

    assert_response :success
    assert_select "strong", text: "Password Updated:"
  end

  test "should show active sessions" do
    login_as(admin_user)
    user = create(:user)

    get admin_user_path(user)

    assert_response :success
    assert_select "h3", text: "Active Sessions"
  end

  test "should show email change link" do
    login_as(admin_user)
    user = create(:user)

    get admin_user_path(user)

    assert_response :success
    assert_select "a[href='#{edit_admin_user_email_update_path(user)}']", text: "Change Email"
  end

  test "should show password reset link" do
    login_as(admin_user)
    user = create(:user)

    get admin_user_path(user)

    assert_response :success
    assert_select "a[href='#{admin_user_password_reset_path(user)}']", text: "Reset Password"
  end

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
