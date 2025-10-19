require "test_helper"

class Admin::SystemStatsControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= begin
      user = create(:user)
      create(:permission, user: user, name: "admin")
      user
    end
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "should redirect non-admin users" do
    login_as(regular_user)

    get admin_system_stats_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users" do
    get admin_system_stats_path

    assert_redirected_to new_session_path
  end

  test "should show system stats for admin users" do
    login_as(admin_user)

    get admin_system_stats_path

    assert_response :success
  end

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
