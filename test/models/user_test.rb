require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup { freeze_time }

  teardown { travel_back }

  test "should be valid with email and password" do
    user = build(:user)
    assert user.valid?
  end

  test "should require email address" do
    user = build(:user, email_address: nil)
    assert_not user.valid?
    assert user.errors.of_kind?(:email_address, :blank)
  end

  test "should require unique email address" do
    existing_user = create(:user)
    user = build(:user, email_address: existing_user.email_address)
    assert_not user.valid?
    assert_includes user.errors[:base], "email is already taken"
  end

  test "should authenticate with correct password" do
    user = create(:user)
    assert user.authenticate("password123")
  end

  test "should not authenticate with wrong password" do
    user = create(:user)
    assert_not user.authenticate("wrong_password")
  end

  test "should authenticate by email and password" do
    user = create(:user)
    authenticated_user = User.authenticate_by(email_address: user.email_address, password: "password123")
    assert_equal user, authenticated_user
  end

  test "should not authenticate with wrong email or password" do
    authenticated_user = User.authenticate_by(email_address: "wrong@example.com", password: "password")
    assert_nil authenticated_user
  end

  test "should have inactive state by default" do
    user = User.new
    assert user.inactive?
  end

  test "#suspend! should change state to suspended and set suspended_at" do
    user = create(:user)
    user.suspend!
    assert user.suspended?
    assert_equal Time.current, user.suspended_at
  end

  test "#unsuspend! should change state to active and clear suspended_at" do
    user = create(:user, :suspended)
    user.unsuspend!
    assert user.active?
    assert_nil user.suspended_at
  end

  test "should have many feeds" do
    user = create(:user)
    feed1 = create(:feed, user: user)
    feed2 = create(:feed, user: user)

    assert_equal 2, user.feeds.count
    assert_includes user.feeds, feed1
    assert_includes user.feeds, feed2
  end

  test "should destroy associated feeds when user is destroyed" do
    user = create(:user)
    create(:feed, user: user)
    create(:feed, user: user)

    assert_difference("Feed.count", -2) do
      user.destroy!
    end
  end

  test "should have many permissions" do
    user = create(:user)
    permission = create(:permission, user: user, name: "admin")

    assert_equal 1, user.permissions.count
    assert_includes user.permissions, permission
  end

  test "should destroy associated permissions when user is destroyed" do
    user = create(:user)
    create(:permission, user: user, name: "admin")

    assert_difference("Permission.count", -1) do
      user.destroy!
    end
  end

  test "should have many access_tokens" do
    user = create(:user)
    token1 = create(:access_token, user: user)
    token2 = create(:access_token, user: user)

    assert_equal 2, user.access_tokens.count
    assert_includes user.access_tokens, token1
    assert_includes user.access_tokens, token2
  end

  test "should destroy associated access_tokens when user is destroyed" do
    user = create(:user)
    create(:access_token, user: user)
    create(:access_token, user: user)

    assert_difference("AccessToken.count", -2) do
      user.destroy!
    end
  end

  test "#admin? returns true when user has admin permission" do
    user = create(:user, :admin)

    assert user.admin?
  end

  test "#total_feeds_count returns count of all user's feeds" do
    user = create(:user)
    create(:feed, user: user)
    create(:feed, user: user)
    other_user = create(:user)
    create(:feed, user: other_user)

    assert_equal 2, user.total_feeds_count
  end

  test "#total_imported_posts_count returns count of all posts across user's feeds" do
    user = create(:user)
    feed1 = create(:feed, user: user)
    feed2 = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed1)
    entry2 = create(:feed_entry, feed: feed2)
    entry3 = create(:feed_entry, feed: feed1)
    create(:post, feed: feed1, feed_entry: entry1)
    create(:post, feed: feed2, feed_entry: entry2)
    create(:post, feed: feed1, feed_entry: entry3)

    other_user = create(:user)
    other_feed = create(:feed, user: other_user)
    other_entry = create(:feed_entry, feed: other_feed)
    create(:post, feed: other_feed, feed_entry: other_entry)

    assert_equal 3, user.total_imported_posts_count
  end

  test "#total_published_posts_count returns count of only published posts" do
    user = create(:user)
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    entry3 = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry1, status: :published)
    create(:post, feed: feed, feed_entry: entry2, status: :published)
    create(:post, feed: feed, feed_entry: entry3, status: :draft)

    assert_equal 2, user.total_published_posts_count
  end

  test "#most_recent_post_published_at returns timestamp of most recent published post" do
    user = create(:user)
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    entry3 = create(:feed_entry, feed: feed)

    create(:post, feed: feed, feed_entry: entry1, status: :published, published_at: 3.days.ago)
    create(:post, feed: feed, feed_entry: entry2, status: :published, published_at: 1.day.ago)
    create(:post, feed: feed, feed_entry: entry3, status: :draft, published_at: Time.current)

    assert_in_delta 1.day.ago.to_i, user.most_recent_post_published_at.to_i, 1
  end

  test "#most_recent_post_published_at returns nil when no published posts" do
    user = create(:user)
    feed = create(:feed, user: user)
    entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry, status: :draft)

    assert_nil user.most_recent_post_published_at
  end

  test "#average_posts_per_day_last_week calculates average correctly" do
    user = create(:user)
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    entry3 = create(:feed_entry, feed: feed)

    create(:post, feed: feed, feed_entry: entry1, published_at: 2.days.ago)
    create(:post, feed: feed, feed_entry: entry2, published_at: 1.day.ago)
    create(:post, feed: feed, feed_entry: entry3, published_at: 10.days.ago)

    assert_equal 0.3, user.average_posts_per_day_last_week
  end

  test "#average_posts_per_day_last_week returns 0.0 when no posts" do
    user = create(:user)

    assert_equal 0.0, user.average_posts_per_day_last_week
  end

  test "#deactivate_email! should set email_deactivated_at and reason" do
    user = create(:user)
    user.deactivate_email!(reason: "bounced")
    assert_equal Time.current, user.email_deactivated_at
    assert_equal "bounced", user.email_deactivation_reason
  end

  test "#email_deactivated? returns true when email_deactivated_at is present" do
    user = create(:user)
    user.deactivate_email!(reason: "bounced")
    assert user.email_deactivated?
  end

  test "#email_deactivated? returns false when email_deactivated_at is nil" do
    user = create(:user)
    assert_not user.email_deactivated?
  end

  test "#reactivate_email! should clear email_deactivated_at and reason" do
    user = create(:user)
    user.deactivate_email!(reason: "bounced")
    user.reactivate_email!
    assert_nil user.email_deactivated_at
    assert_nil user.email_deactivation_reason
  end

  test "#can_change_email? returns true when no email change events exist" do
    user = create(:user)
    assert user.can_change_email?
  end

  test "#can_change_email? returns true when last email change was more than 24 hours ago" do
    user = create(:user)
    travel_to 25.hours.ago do
      Event.create!(
        type: "EmailChanged",
        level: :info,
        subject: user,
        user: user,
        message: "Email changed from old@example.com to #{user.email_address}",
        metadata: { old_email: "old@example.com", new_email: user.email_address }
      )
    end
    assert user.can_change_email?
  end

  test "#can_change_email? returns false when last email change was less than 24 hours ago" do
    user = create(:user)
    Event.create!(
      type: "EmailChanged",
      level: :info,
      subject: user,
      user: user,
      message: "Email changed from old@example.com to #{user.email_address}",
      metadata: { old_email: "old@example.com", new_email: user.email_address }
    )
    assert_not user.can_change_email?
  end

  test "#time_until_email_change_allowed returns 0 when user can change email" do
    user = create(:user)
    assert_equal 0, user.time_until_email_change_allowed
  end

  test "#time_until_email_change_allowed returns remaining time when rate limited" do
    user = create(:user)
    time_elapsed = User::EMAIL_CHANGE_COOLDOWN / 2

    travel_to time_elapsed.ago do
      Event.create!(
        type: "EmailChanged",
        level: :info,
        subject: user,
        user: user,
        message: "Email changed from old@example.com to #{user.email_address}",
        metadata: { old_email: "old@example.com", new_email: user.email_address }
      )
    end

    expected_remaining = User::EMAIL_CHANGE_COOLDOWN - time_elapsed
    assert_equal expected_remaining, user.time_until_email_change_allowed
  end

  test "#last_email_change_event returns most recent EmailChanged" do
    user = create(:user)

    old_event = travel_to((User::EMAIL_CHANGE_COOLDOWN * 2).ago) do
      Event.create!(
        type: "EmailChanged",
        level: :info,
        subject: user,
        user: user,
        message: "Email changed from old1@example.com to old2@example.com",
        metadata: { old_email: "old1@example.com", new_email: "old2@example.com" }
      )
    end

    recent_event = Event.create!(
      type: "EmailChanged",
      level: :info,
      subject: user,
      user: user,
      message: "Email changed from old2@example.com to #{user.email_address}",
      metadata: { old_email: "old2@example.com", new_email: user.email_address }
    )

    assert_equal recent_event, user.last_email_change_event
  end
end
