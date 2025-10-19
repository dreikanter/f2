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
    assert_not_nil assigns(:disk_usage)
  end

  test "should return disk usage with expected structure" do
    login_as(admin_user)

    get admin_system_stats_path

    disk_usage = assigns(:disk_usage)

    assert disk_usage.key?(:free_space)
    assert disk_usage.key?(:postgres_usage)
    assert disk_usage.key?(:table_usage)
    assert disk_usage.key?(:vacuum_stats)
    assert disk_usage.key?(:autovacuum_settings)

    assert disk_usage[:table_usage].is_a?(Array)
    assert disk_usage[:vacuum_stats].is_a?(Array)
    assert disk_usage[:autovacuum_settings].is_a?(Array)
  end
end
