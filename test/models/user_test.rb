require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup { freeze_time }

  teardown { travel_back }

  test "#valid? should return true with email and password" do
    user = build(:user)
    assert user.valid?
  end

  test "#valid? should require email address" do
    user = build(:user, email_address: nil)
    assert_not user.valid?
    assert user.errors.of_kind?(:email_address, :blank)
  end

  test "#valid? should require unique email address" do
    existing_user = create(:user)
    user = build(:user, email_address: existing_user.email_address)
    assert_not user.valid?
    assert_includes user.errors[:base], "email is already taken"
  end

  test "#valid? should allow a blank name" do
    user = build(:user, name: "")
    assert user.valid?
  end

  test "#valid? should reject a name longer than the limit" do
    user = build(:user, name: "a" * (User::NAME_MAX_LENGTH + 1))
    assert_not user.valid?
    assert user.errors.of_kind?(:name, :too_long)
  end

  test "#name= should strip surrounding whitespace from the name" do
    user = build(:user, name: "  Alex  ")
    assert_equal "Alex", user.name
  end

  test "#update should let an account with a legacy over-long name update other attributes" do
    user = create(:user)
    user.update_column(:name, "a" * (User::NAME_MAX_LENGTH + 1))

    assert user.reload.update(password: "brandnewpassword")
  end

  test "#update should still reject shortening a legacy name to another over-long value" do
    user = create(:user)
    user.update_column(:name, "a" * (User::NAME_MAX_LENGTH + 10))

    assert_not user.reload.update(name: "b" * (User::NAME_MAX_LENGTH + 1))
  end

  test "#anonymized_email should keep first and last local characters with full domain" do
    user = build(:user, email_address: "username@gmail.com")
    assert_equal "u...e@gmail.com", user.anonymized_email
  end

  test "#anonymized_email should handle a single-character local part" do
    user = build(:user, email_address: "a@example.com")
    assert_equal "a...@example.com", user.anonymized_email
  end

  test "#anonymized_email should mask the whole value when there is no domain" do
    user = build(:user, email_address: "username")
    assert_equal "u...e", user.anonymized_email
  end

  test "#authenticate should return the user with the correct password" do
    user = create(:user)
    assert user.authenticate("password123")
  end

  test "#authenticate should return false with the wrong password" do
    user = create(:user)
    assert_not user.authenticate("wrong_password")
  end

  test ".authenticate_by should return the user with matching email and password" do
    user = create(:user)
    authenticated_user = User.authenticate_by(email_address: user.email_address, password: "password123")
    assert_equal user, authenticated_user
  end

  test ".authenticate_by should return nil with the wrong email or password" do
    authenticated_user = User.authenticate_by(email_address: "wrong@example.com", password: "password")
    assert_nil authenticated_user
  end

  test ".find_by_password_reset_token should reject expired tokens" do
    user = create(:user)
    token = user.generate_token_for(:password_reset)

    travel(User::PASSWORD_RESET_TTL - 1.second) do
      assert_equal user, User.find_by_password_reset_token(token)
    end

    travel(User::PASSWORD_RESET_TTL + 1.second) do
      assert_nil User.find_by_password_reset_token(token)
    end
  end

  test "#initialize should default state to inactive" do
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

  test "#confirm_email! should move an inactive user to active" do
    user = create(:user, :inactive)
    user.confirm_email!
    assert user.active?
  end

  test "#confirm_email! should not change the state of an already confirmed user" do
    user = create(:user, state: :active)
    user.confirm_email!
    assert user.active?
  end

  test "#email_confirmed? should return false for an inactive user" do
    assert_not create(:user, :inactive).email_confirmed?
  end

  test "#email_confirmed? should return true once the user is past inactive" do
    assert create(:user, :suspended).email_confirmed?
    assert create(:user, state: :active).email_confirmed?
  end

  test "#feeds should return the associated feeds" do
    user = create(:user)
    feed1 = create(:feed, user: user)
    feed2 = create(:feed, user: user)

    assert_equal 2, user.feeds.count
    assert_includes user.feeds, feed1
    assert_includes user.feeds, feed2
  end

  test "#destroy! should remove associated feeds" do
    user = create(:user)
    create(:feed, user: user)
    create(:feed, user: user)

    assert_difference("Feed.count", -2) do
      user.destroy!
    end
  end

  test "#permissions should return the associated permissions" do
    user = create(:user)
    permission = create(:permission, user: user, name: "admin")

    assert_equal 1, user.permissions.count
    assert_includes user.permissions, permission
  end

  test "#destroy! should remove associated permissions" do
    user = create(:user)
    create(:permission, user: user, name: "admin")

    assert_difference("Permission.count", -1) do
      user.destroy!
    end
  end

  test "#access_tokens should return the associated access tokens" do
    user = create(:user)
    token1 = create(:access_token, user: user)
    token2 = create(:access_token, user: user)

    assert_equal 2, user.access_tokens.count
    assert_includes user.access_tokens, token1
    assert_includes user.access_tokens, token2
  end

  test "#destroy! should remove associated access tokens" do
    user = create(:user)
    create(:access_token, user: user)
    create(:access_token, user: user)

    assert_difference("AccessToken.count", -2) do
      user.destroy!
    end
  end

  test "#destroy! should nullify the user on associated events" do
    user = create(:user)
    event = create(:event, user: user)

    assert_no_difference("Event.count") do
      user.destroy!
    end

    assert_nil event.reload.user_id
  end

  test "#admin? should return true when user has admin permission" do
    user = create(:user, :admin)

    assert user.admin?
  end

  test "#total_feeds_count should return count of all user's feeds" do
    user = create(:user)
    create(:feed, user: user)
    create(:feed, user: user)
    other_user = create(:user)
    create(:feed, user: other_user)

    assert_equal 2, user.total_feeds_count
  end

  test "#total_imported_posts_count should return count of all posts across user's feeds" do
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

  test "#total_published_posts_count should return count of only published posts" do
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

  test "#most_recent_repost_at should return the most recent repost timestamp regardless of original publication date" do
    user = create(:user)
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    entry3 = create(:feed_entry, feed: feed)

    # Older original publication date, but reposted most recently.
    create(:post, feed: feed, feed_entry: entry1, status: :published, published_at: 10.days.ago, reposted_at: 1.hour.ago)
    create(:post, feed: feed, feed_entry: entry2, status: :published, published_at: 1.day.ago, reposted_at: 2.days.ago)
    create(:post, feed: feed, feed_entry: entry3, status: :draft, updated_at: Time.current)

    assert_in_delta 1.hour.ago.to_i, user.most_recent_repost_at.to_i, 1
  end

  test "#most_recent_repost_at should return nil when no published posts" do
    user = create(:user)
    feed = create(:feed, user: user)
    entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry, status: :draft)

    assert_nil user.most_recent_repost_at
  end

  test "#posts_published_last_week_count should return count of published posts from the last 7 days" do
    user = create(:user)
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    entry3 = create(:feed_entry, feed: feed)

    create(:post, :published, feed: feed, feed_entry: entry1, published_at: 2.days.ago)
    create(:post, :published, feed: feed, feed_entry: entry2, published_at: 1.day.ago)
    create(:post, :published, feed: feed, feed_entry: entry3, published_at: 10.days.ago)

    assert_equal 2, user.posts_published_last_week_count
  end

  test "#posts_published_last_week_count should ignore posts that are not published" do
    user = create(:user)
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)

    create(:post, feed: feed, feed_entry: entry1, published_at: 1.day.ago)
    create(:post, :published, feed: feed, feed_entry: entry2, published_at: 1.day.ago)

    assert_equal 1, user.posts_published_last_week_count
  end

  test "#posts_published_last_week_count should return 0 when no posts" do
    user = create(:user)

    assert_equal 0, user.posts_published_last_week_count
  end

  test "#deactivate_email! should set email_deactivated_at and reason" do
    user = create(:user)
    user.deactivate_email!(reason: "bounced")
    assert_equal Time.current, user.email_deactivated_at
    assert_equal "bounced", user.email_deactivation_reason
  end

  test "#email_deactivated? should return true when email_deactivated_at is present" do
    user = create(:user)
    user.deactivate_email!(reason: "bounced")
    assert user.email_deactivated?
  end

  test "#email_deactivated? should return false when email_deactivated_at is nil" do
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

  test "#can_change_email? should return true when no email change events exist" do
    user = create(:user)
    assert user.can_change_email?
  end

  test "#can_change_email? should return true when last email change was more than 24 hours ago" do
    user = create(:user)
    travel_to 25.hours.ago do
      Event.create!(
        type: "email_changed",
        level: :info,
        subject: user,
        user: user,
        message: "Email changed from old@example.com to #{user.email_address}",
        metadata: { old_email: "old@example.com", new_email: user.email_address }
      )
    end
    assert user.can_change_email?
  end

  test "#can_change_email? should return false when last email change was less than 24 hours ago" do
    user = create(:user)
    Event.create!(
      type: "email_changed",
      level: :info,
      subject: user,
      user: user,
      message: "Email changed from old@example.com to #{user.email_address}",
      metadata: { old_email: "old@example.com", new_email: user.email_address }
    )
    assert_not user.can_change_email?
  end

  test "#time_until_email_change_allowed should return 0 when user can change email" do
    user = create(:user)
    assert_equal 0, user.time_until_email_change_allowed
  end

  test "#time_until_email_change_allowed should return remaining time when rate limited" do
    user = create(:user)
    time_elapsed = User::EMAIL_CHANGE_COOLDOWN / 2

    travel_to time_elapsed.ago do
      Event.create!(
        type: "email_changed",
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

  test "#last_email_change_event should return most recent EmailChanged" do
    user = create(:user)

    old_event = travel_to((User::EMAIL_CHANGE_COOLDOWN * 2).ago) do
      Event.create!(
        type: "email_changed",
        level: :info,
        subject: user,
        user: user,
        message: "Email changed from old1@example.com to old2@example.com",
        metadata: { old_email: "old1@example.com", new_email: "old2@example.com" }
      )
    end

    recent_event = Event.create!(
      type: "email_changed",
      level: :info,
      subject: user,
      user: user,
      message: "Email changed from old2@example.com to #{user.email_address}",
      metadata: { old_email: "old2@example.com", new_email: user.email_address }
    )

    assert_equal recent_event, user.last_email_change_event
  end
end
