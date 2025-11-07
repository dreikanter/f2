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

    4.times { create(:user) }

    get admin_users_path, params: { per_page: 3 }

    assert_response :success
    assert_select "nav[aria-label='Users pagination']"
    assert_select "tbody tr", count: 3
  end

  test "should display only total when feeds counts are zero" do
    login_as(admin_user)
    user = create(:user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.feeds.value']", text: /^0 total$/
  end

  test "should hide zero enabled count" do
    login_as(admin_user)
    user = create(:user)
    create(:feed, user: user, state: :disabled)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.feeds.value']", text: /^1 total \(1 disabled\)$/
    assert_select "[data-key='stats.feeds.value']", text: /enabled/, count: 0
  end

  test "should hide zero disabled count" do
    login_as(admin_user)
    user = create(:user)
    create(:feed, user: user, state: :enabled)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.feeds.value']", text: /^1 total \(1 enabled\)$/
    assert_select "[data-key='stats.feeds.value']", text: /disabled/, count: 0
  end

  test "should display both enabled and disabled counts when non-zero" do
    login_as(admin_user)
    user = create(:user)
    create(:feed, user: user, state: :enabled)
    create(:feed, user: user, state: :disabled)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.feeds.value']", text: "2 total (1 enabled, 1 disabled)"
  end

  test "should display only total when access token counts are zero" do
    login_as(admin_user)
    user = create(:user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.access_tokens.value']", text: /^0 total$/
  end

  test "should hide zero active token count" do
    login_as(admin_user)
    user = create(:user)
    create(:access_token, :inactive, user: user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.access_tokens.value']", text: /^1 total \(1 not active\)$/
  end

  test "should hide zero inactive token count" do
    login_as(admin_user)
    user = create(:user)
    create(:access_token, :active, user: user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.access_tokens.value']", text: /^1 total \(1 active\)$/
    assert_select "[data-key='stats.access_tokens.value']", text: /not active/, count: 0
  end

  test "should display both active and inactive token counts when non-zero" do
    login_as(admin_user)
    user = create(:user)
    create(:access_token, :active, user: user)
    create(:access_token, :inactive, user: user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.access_tokens.value']", text: "2 total (1 active, 1 not active)"
  end

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
