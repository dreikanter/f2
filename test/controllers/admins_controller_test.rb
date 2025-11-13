require "test_helper"

class AdminsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def admin_user
    @admin_user ||= begin
      admin = create(:user)
      create(:permission, user: admin, name: "admin")
      admin
    end
  end

  test "should show admin panel when authenticated as admin" do
    sign_in_as(admin_user)
    get admin_url

    assert_response :success
    assert_select "h1", "Admin Panel"
    assert_select "a.ff-card[href='#{admin_users_path}']", count: 1
    assert_select "a.ff-card[href='#{admin_events_path}']", count: 1
    assert_select "a.ff-card[href='#{admin_system_stats_path}']", count: 1
    assert_select "a.ff-card[href='/jobs']", count: 1
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
