require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "should get show when authenticated" do
    user = users(:one)
    sign_in_as(user)
    
    get dashboard_url
    assert_response :success
  end
  
  test "should redirect to sign in when not authenticated" do
    get dashboard_url
    assert_redirected_to new_session_url
  end
  
  test "should redirect to dashboard from root" do
    user = users(:one)
    sign_in_as(user)
    
    get root_url
    assert_response :success
  end
end
