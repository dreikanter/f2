require "test_helper"

class AdminsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def admin_dev_user
    @admin_dev_user ||= create(:user, :admin, :dev)
  end

  test "should show admin panel when authenticated as admin" do
    sign_in_as(admin_user)
    get admin_url

    assert_response :success
    assert_select "h1", "Admin Panel"
    assert_select "a[href='#{admin_users_path}']", count: 1
    assert_select "a[href='#{admin_events_path}']", count: 1
    assert_select "a[href='#{development_system_status_path}']", count: 0
    assert_select "a[href='#{development_components_path}']", count: 0
  end

  test "should not show dev cards on admin panel for admin with dev permission" do
    sign_in_as(admin_dev_user)
    get admin_url

    assert_response :success
    assert_select "a[href='#{admin_users_path}']", count: 1
    assert_select "a[href='#{admin_events_path}']", count: 1
    assert_select "a[href='#{development_system_status_path}']", count: 0
    assert_select "a[href='#{mission_control_jobs.root_path}']", count: 0
    assert_select "a[href='#{development_sent_emails_path}']", count: 0
    assert_select "a[href='#{development_components_path}']", count: 0
  end

  test "should redirect when authenticated as regular user" do
    sign_in_as(user)
    get admin_url

    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect when not authenticated" do
    get admin_url

    assert_response :redirect
  end
end
