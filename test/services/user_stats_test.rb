require "test_helper"

class UserStatsTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def stats
    @stats ||= UserStats.new(user)
  end

  test "#last_session should return most recent session" do
    session1 = create(:session, user: user, updated_at: 1.day.ago)
    session2 = create(:session, user: user, updated_at: 1.hour.ago)

    assert_equal session2, UserStats.new(user).last_session
  end

  test "#last_session should return nil when no sessions" do
    assert_nil UserStats.new(user).last_session
  end

  test "#sessions should return all sessions ordered by updated_at desc" do
    session1 = create(:session, user: user, updated_at: 2.days.ago)
    session2 = create(:session, user: user, updated_at: 1.hour.ago)
    session3 = create(:session, user: user, updated_at: 1.day.ago)

    sessions = UserStats.new(user).sessions
    assert_equal [session2, session3, session1], sessions
  end

  test "#feeds_count should return total number of feeds" do
    create(:feed, user: user, state: :enabled)
    create(:feed, user: user, state: :disabled)

    assert_equal 2, UserStats.new(user).feeds_count
  end

  test "#feeds_enabled_count should return count of enabled feeds" do
    create(:feed, user: user, state: :enabled)
    create(:feed, user: user, state: :enabled)
    create(:feed, user: user, state: :disabled)

    assert_equal 2, UserStats.new(user).feeds_enabled_count
  end

  test "#feeds_disabled_count should return count of disabled feeds" do
    create(:feed, user: user, state: :enabled)
    create(:feed, user: user, state: :disabled)
    create(:feed, user: user, state: :disabled)

    assert_equal 2, UserStats.new(user).feeds_disabled_count
  end

  test "#access_tokens_count should return total number of access tokens" do
    create(:access_token, user: user, status: :active)
    create(:access_token, user: user, status: :inactive)

    assert_equal 2, UserStats.new(user).access_tokens_count
  end

  test "#active_access_tokens_count should return count of active tokens" do
    create(:access_token, user: user, status: :active)
    create(:access_token, user: user, status: :active)
    create(:access_token, user: user, status: :inactive)

    assert_equal 2, UserStats.new(user).active_access_tokens_count
  end

  test "#inactive_access_tokens_count should return count of inactive tokens" do
    create(:access_token, user: user, status: :active)
    create(:access_token, user: user, status: :inactive)
    create(:access_token, user: user, status: :inactive)

    assert_equal 2, UserStats.new(user).inactive_access_tokens_count
  end

  test "#posts_count should return total number of posts" do
    feed = create(:feed, user: user)
    create(:post, feed: feed)
    create(:post, feed: feed)

    assert_equal 2, UserStats.new(user).posts_count
  end

  test "#most_recent_post should return latest post" do
    feed = create(:feed, user: user)
    post1 = create(:post, feed: feed, published_at: 2.days.ago)
    post2 = create(:post, feed: feed, published_at: 1.hour.ago)

    assert_equal post2, UserStats.new(user).most_recent_post
  end

  test "#most_recent_post should return nil when no posts" do
    assert_nil UserStats.new(user).most_recent_post
  end

  test "#created_invites_count should return total number of invitations" do
    create(:invite, created_by_user: user)
    create(:invite, created_by_user: user)

    assert_equal 2, UserStats.new(user).created_invites_count
  end

  test "#invited_users_count should return count of invitations with invited user" do
    create(:invite, created_by_user: user, invited_user: create(:user))
    create(:invite, created_by_user: user, invited_user: create(:user))
    create(:invite, created_by_user: user, invited_user: nil)

    assert_equal 2, UserStats.new(user).invited_users_count
  end

  test "#invited_users should return invitations with invited user ordered by created_at desc" do
    inv1 = create(:invite, created_by_user: user, invited_user: create(:user), created_at: 2.days.ago)
    inv2 = create(:invite, created_by_user: user, invited_user: create(:user), created_at: 1.hour.ago)
    inv3 = create(:invite, created_by_user: user, invited_user: nil)

    invited_users = UserStats.new(user).invited_users
    assert_equal [inv2, inv1], invited_users
  end
end
