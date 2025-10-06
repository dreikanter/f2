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

    30.times { create(:user) }

    get admin_users_path

    assert_response :success
    assert_select ".pagination"
    assert_select "tbody tr", count: 25
  end

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
