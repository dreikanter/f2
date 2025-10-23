require "test_helper"

class FeedEntryUidTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed)
  end

  test "should be valid with all required attributes" do
    feed_entry_uid = build(
      :feed_entry_uid,
      feed: feed,
      uid: "test-uid-123",
      imported_at: Time.current
    )

    assert feed_entry_uid.valid?
  end

  test "should require uid" do
    feed_entry_uid = build(:feed_entry_uid, feed: feed, uid: nil)
    assert_not feed_entry_uid.valid?
    assert feed_entry_uid.errors.of_kind?(:uid, :blank)
  end

  test "should require imported_at" do
    feed_entry_uid = build(:feed_entry_uid, feed: feed, uid: "test-uid", imported_at: nil)
    assert_not feed_entry_uid.valid?
    assert feed_entry_uid.errors.of_kind?(:imported_at, :blank)
  end

  test "should enforce uniqueness of uid scoped to feed" do
    create(:feed_entry_uid, feed: feed, uid: "duplicate-uid")
    duplicate = build(:feed_entry_uid, feed: feed, uid: "duplicate-uid")

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:uid, :taken)
  end

  test "should allow same uid for different feeds" do
    other_feed = create(:feed)
    create(:feed_entry_uid, feed: feed, uid: "same-uid")
    other_uid = build(:feed_entry_uid, feed: other_feed, uid: "same-uid")

    assert other_uid.valid?
  end

  test "should belong to a feed" do
    feed_entry_uid = create(:feed_entry_uid, feed: feed)
    assert_equal feed, feed_entry_uid.feed
  end
end
