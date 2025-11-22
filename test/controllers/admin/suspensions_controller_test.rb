require "test_helper"

class Admin::SuspensionsControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def target_user
    @target_user ||= create(:user)
  end

  test "#create should suspend user and redirect" do
    sign_in_as admin_user
    assert target_user.active?

    post admin_user_user_suspension_path(target_user)

    assert_redirected_to admin_user_path(target_user)
    target_user.reload
    assert target_user.suspended?
  end

  test "#create should terminate all user sessions" do
    sign_in_as admin_user
    session1 = target_user.sessions.create!(user_agent: "Browser 1", ip_address: "1.1.1.1")
    session2 = target_user.sessions.create!(user_agent: "Browser 2", ip_address: "2.2.2.2")

    post admin_user_user_suspension_path(target_user)

    assert_equal 0, target_user.reload.sessions.count
  end

  test "#create should disable all enabled feeds" do
    sign_in_as admin_user
    feed1 = create(:feed, :enabled, user: target_user)
    feed2 = create(:feed, :enabled, user: target_user)

    post admin_user_user_suspension_path(target_user)

    assert_equal "disabled", feed1.reload.state
    assert_equal "disabled", feed2.reload.state
  end

  test "#destroy should unsuspend user and redirect" do
    sign_in_as admin_user
    suspended_user = create(:user, :suspended)

    delete admin_user_user_suspension_path(suspended_user)

    assert_redirected_to admin_user_path(suspended_user)
    suspended_user.reload
    assert suspended_user.active?
  end

  test "#destroy should not re-enable feeds" do
    sign_in_as admin_user
    feed1 = create(:feed, :enabled, user: target_user)
    feed2 = create(:feed, :enabled, user: target_user)

    post admin_user_user_suspension_path(target_user)

    delete admin_user_user_suspension_path(target_user)

    assert_equal "disabled", feed1.reload.state
    assert_equal "disabled", feed2.reload.state
  end

  test "#create should require admin permission" do
    sign_in_as create(:user)

    post admin_user_user_suspension_path(target_user)

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#destroy should require admin permission" do
    sign_in_as create(:user)
    suspended_user = create(:user, :suspended)

    delete admin_user_user_suspension_path(suspended_user)

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#create should record user_suspended event with deactivated feed IDs" do
    sign_in_as admin_user
    feed1 = create(:feed, :enabled, user: target_user)
    feed2 = create(:feed, :enabled, user: target_user)
    feed3 = create(:feed, :disabled, user: target_user)

    assert_difference "Event.count", 1 do
      post admin_user_user_suspension_path(target_user)
    end

    event = Event.last
    assert_equal "user_suspended", event.type
    assert_equal admin_user, event.user
    assert_equal target_user, event.subject
    assert_equal "warning", event.level
    assert_equal [feed1.id, feed2.id].sort, event.metadata["deactivated_feed_ids"].sort
  end

  test "#destroy should record user_unsuspended event" do
    sign_in_as admin_user
    post admin_user_user_suspension_path(target_user)

    assert_difference "Event.count", 1 do
      delete admin_user_user_suspension_path(target_user)
    end

    event = Event.last
    assert_equal "user_unsuspended", event.type
    assert_equal admin_user, event.user
    assert_equal target_user, event.subject
    assert_equal "info", event.level
  end
end
