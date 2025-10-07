require "test_helper"

class Admin::UserSuspensionsControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def target_user
    @target_user ||= create(:user)
  end

  test "create suspends user and redirects" do
    sign_in_as admin_user
    assert_not target_user.suspended?

    post admin_user_suspension_path(target_user)

    assert_redirected_to admin_user_path(target_user)
    assert_equal "User has been suspended.", flash[:notice]
    assert target_user.reload.suspended?
  end

  test "create terminates all user sessions" do
    sign_in_as admin_user
    session1 = target_user.sessions.create!(user_agent: "Browser 1", ip_address: "1.1.1.1")
    session2 = target_user.sessions.create!(user_agent: "Browser 2", ip_address: "2.2.2.2")

    post admin_user_suspension_path(target_user)

    assert_equal 0, target_user.reload.sessions.count
  end

  test "create disables all enabled feeds" do
    sign_in_as admin_user
    feed1 = create(:feed, :enabled, user: target_user)
    feed2 = create(:feed, :enabled, user: target_user)
    feed3 = create(:feed, :disabled, user: target_user)

    post admin_user_suspension_path(target_user)

    assert_equal "disabled", feed1.reload.state
    assert_equal "disabled", feed2.reload.state
    assert_equal "disabled", feed3.reload.state
  end

  test "destroy unsuspends user and redirects" do
    sign_in_as admin_user
    post admin_user_suspension_path(target_user)
    assert target_user.reload.suspended?

    delete admin_user_suspension_path(target_user)

    assert_redirected_to admin_user_path(target_user)
    assert_equal "User has been unsuspended.", flash[:notice]
    assert_not target_user.reload.suspended?
  end

  test "destroy does not re-enable feeds" do
    sign_in_as admin_user
    feed1 = create(:feed, :enabled, user: target_user)
    feed2 = create(:feed, :enabled, user: target_user)

    post admin_user_suspension_path(target_user)

    delete admin_user_suspension_path(target_user)

    assert_equal "disabled", feed1.reload.state
    assert_equal "disabled", feed2.reload.state
  end

  test "requires admin permission for create" do
    sign_in_as create(:user)

    post admin_user_suspension_path(target_user)

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "requires admin permission for destroy" do
    sign_in_as create(:user)
    target_user.suspend!

    delete admin_user_suspension_path(target_user)

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "create records UserSuspended event with deactivated feed IDs" do
    sign_in_as admin_user
    feed1 = create(:feed, :enabled, user: target_user)
    feed2 = create(:feed, :enabled, user: target_user)
    feed3 = create(:feed, :disabled, user: target_user)

    assert_difference "Event.count", 1 do
      post admin_user_suspension_path(target_user)
    end

    event = Event.last
    assert_equal "UserSuspended", event.type
    assert_equal admin_user, event.user
    assert_equal target_user, event.subject
    assert_equal "warning", event.level
    assert_equal [feed1.id, feed2.id].sort, event.metadata["deactivated_feed_ids"].sort
  end

  test "destroy records UserUnsuspended event" do
    sign_in_as admin_user
    post admin_user_suspension_path(target_user)

    assert_difference "Event.count", 1 do
      delete admin_user_suspension_path(target_user)
    end

    event = Event.last
    assert_equal "UserUnsuspended", event.type
    assert_equal admin_user, event.user
    assert_equal target_user, event.subject
    assert_equal "info", event.level
  end
end
