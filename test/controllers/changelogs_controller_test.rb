require "test_helper"

class ChangelogsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "should redirect to login when not authenticated" do
    get changelog_url
    assert_redirected_to new_session_path
  end

  test "should show changelog when authenticated" do
    sign_in_as user
    get changelog_url

    assert_response :success
    assert_select "h1", text: "Changelog"
    assert_select '[data-key="changelog.sections"] section h2', minimum: 1
    assert_select '[data-key="changelog.sections"] section li', minimum: 1
  end
end
