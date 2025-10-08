require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "requires authentication" do
    get dashboard_path
    assert_redirected_to new_session_path
  end

  test "shows dashboard when authenticated" do
    sign_in_as user
    get dashboard_path
    assert_response :success
    assert_select "h1", "Dashboard"
  end
end
