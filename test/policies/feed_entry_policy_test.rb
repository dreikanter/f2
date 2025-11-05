require "test_helper"

class FeedEntryPolicyTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  def other_feed
    @other_feed ||= create(:feed, user: other_user)
  end

  def user_feed_entry
    @user_feed_entry ||= create(:feed_entry, feed: feed)
  end

  def other_user_feed_entry
    @other_user_feed_entry ||= create(:feed_entry, feed: other_feed)
  end

  test "#show? should allow owner" do
    assert FeedEntryPolicy.new(user, user_feed_entry).show?
  end

  test "#show? should deny non-owner" do
    assert_not FeedEntryPolicy.new(user, other_user_feed_entry).show?
  end

  test "#show? should deny unauthenticated users" do
    assert_not FeedEntryPolicy.new(nil, user_feed_entry).show?
  end

  test "Scope returns user's feed entries only" do
    create(:feed_entry, feed: feed)
    create(:feed_entry, feed: other_feed)

    resolved_entries = FeedEntryPolicy::Scope.new(user, FeedEntry).resolve
    assert_equal 1, resolved_entries.count
    assert_equal feed.id, resolved_entries.first.feed_id
  end

  test "Scope should return empty for unauthenticated users" do
    create(:feed_entry, feed: feed)
    resolved_entries = FeedEntryPolicy::Scope.new(nil, FeedEntry).resolve
    assert_equal 0, resolved_entries.count
  end
end
