require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "should redirect non-admin users from index" do
    sign_in_as(regular_user)

    get admin_users_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users from index" do
    get admin_users_path

    assert_redirected_to new_session_path
  end

  test "should allow admin users to view users index" do
    sign_in_as(admin_user)
    other_user = create(:user, email_address: "other@example.com")

    get admin_users_path

    assert_response :success
    assert_select "h1", "Users"
    assert_select "a[href='#{admin_user_path(other_user)}']", text: "other@example.com"
  end

  test "should allow admin users to view user details" do
    sign_in_as(admin_user)
    user = create(:user, email_address: "test@example.com")

    get admin_user_path(user)

    assert_response :success
    assert_select "h1", "test@example.com"
  end

  test "should show active suspend button for other users" do
    sign_in_as(admin_user)
    other_user = create(:user)

    get admin_user_path(other_user)

    assert_response :success
    assert_select "a", text: "Suspend user…"
    assert_select "[data-key='actions.suspend_self_disabled']", count: 0
  end

  test "should disable suspend button for the current admin" do
    sign_in_as(admin_user)

    get admin_user_path(admin_user)

    assert_response :success
    assert_select "[data-key='actions.suspend_self_disabled']", text: "Suspend user…"
    assert_select "a", text: "Suspend user…", count: 0
  end

  test "should show confirm email button for a user with a pending email" do
    sign_in_as(admin_user)
    user = create(:user, :inactive)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='actions.confirm_email']", text: "Confirm Email…"
  end

  test "should confirm email behind a confirmation dialog" do
    sign_in_as(admin_user)
    user = create(:user, :inactive)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='actions.confirm_email'][data-modal-trigger-modal-id-value='confirm-email-modal-#{user.id}']"
    assert_select "#confirm-email-modal-#{user.id} form[action='#{admin_user_email_confirmation_path(user)}']"
  end

  test "should disable confirm email button once the email is confirmed" do
    sign_in_as(admin_user)
    user = create(:user, state: :active)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='actions.confirm_email']", count: 0
    assert_select "[data-key='actions.confirm_email_disabled']", text: "Confirm Email…"
    assert_select "#confirm-email-modal-#{user.id}", count: 0
  end

  test "#show should render a recent activity section with the user's events" do
    sign_in_as(admin_user)
    user = create(:user)
    create(:event, user: user)

    get admin_user_path(user)

    assert_response :success
    assert_select "h2", text: "Recent Activity", count: 1
  end

  test "#show should link recent activity to the events log filtered by user" do
    sign_in_as(admin_user)
    user = create(:user)
    create(:event, user: user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='user.events.view_all'][href=?]", admin_events_path(filter: { user_id: user.id }), text: "View all"
  end

  test "#show should not render recent activity section when user has no events" do
    sign_in_as(admin_user)
    user = create(:user)

    get admin_user_path(user)

    assert_response :success
    assert_select "h2", text: "Recent Activity", count: 0
  end

  test "should redirect non-admin users from show" do
    sign_in_as(regular_user)
    user = create(:user)

    get admin_user_path(user)

    assert_redirected_to root_path
  end

  test "should paginate users" do
    sign_in_as(admin_user)

    4.times { create(:user) }

    get admin_users_path, params: { per_page: 3 }

    assert_response :success
    assert_select "nav[aria-label='Users pagination']"
    assert_select "tbody tr", count: 3
  end

  test "should display only total when feeds counts are zero" do
    sign_in_as(admin_user)
    user = create(:user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.feeds.value']", text: /^0 total$/
  end

  test "should hide zero enabled count" do
    sign_in_as(admin_user)
    user = create(:user)
    create(:feed, user: user, state: :disabled)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.feeds.value']", text: /^1 total \(1 disabled\)$/
    assert_select "[data-key='stats.feeds.value']", text: /enabled/, count: 0
  end

  test "should hide zero disabled count" do
    sign_in_as(admin_user)
    user = create(:user)
    create(:feed, user: user, state: :enabled)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.feeds.value']", text: /^1 total \(1 enabled\)$/
    assert_select "[data-key='stats.feeds.value']", text: /disabled/, count: 0
  end

  test "should display both enabled and disabled counts when non-zero" do
    sign_in_as(admin_user)
    user = create(:user)
    create(:feed, user: user, state: :enabled)
    create(:feed, user: user, state: :disabled)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.feeds.value']", text: "2 total (1 enabled, 1 disabled)"
  end

  test "should display only total when access token counts are zero" do
    sign_in_as(admin_user)
    user = create(:user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.access_tokens.value']", text: /^0 total$/
  end

  test "should hide zero active token count" do
    sign_in_as(admin_user)
    user = create(:user)
    create(:access_token, :inactive, user: user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.access_tokens.value']", text: /^1 total \(1 not active\)$/
  end

  test "should hide zero inactive token count" do
    sign_in_as(admin_user)
    user = create(:user)
    create(:access_token, :active, user: user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.access_tokens.value']", text: /^1 total \(1 active\)$/
    assert_select "[data-key='stats.access_tokens.value']", text: /not active/, count: 0
  end

  test "should display both active and inactive token counts when non-zero" do
    sign_in_as(admin_user)
    user = create(:user)
    create(:access_token, :active, user: user)
    create(:access_token, :inactive, user: user)

    get admin_user_path(user)

    assert_response :success
    assert_select "[data-key='stats.access_tokens.value']", text: "2 total (1 active, 1 not active)"
  end
end
