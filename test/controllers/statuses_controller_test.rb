require "test_helper"

class StatusesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "requires authentication" do
    get status_path
    assert_redirected_to new_session_path
  end

  test "shows status when authenticated" do
    sign_in_as user
    get status_path
    assert_response :success
    assert_select "h1", "Status"
  end
end
