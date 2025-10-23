require "test_helper"

class FeedEntryTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed)
  end

  def valid_feed_entry
    @valid_feed_entry ||= build(:feed_entry, feed: feed)
  end

  test "should be valid with valid attributes" do
    entry = valid_feed_entry
    assert entry.valid?
  end

  test "should require uid" do
    entry = build(:feed_entry, uid: nil)
    assert_not entry.valid?
    assert entry.errors.of_kind?(:uid, :blank)
  end

  test "should require uid to be unique within feed scope" do
    entry1 = create(:feed_entry, feed: feed, uid: "duplicate-uid")
    entry2 = build(:feed_entry, feed: feed, uid: "duplicate-uid")

    assert_not entry2.valid?
    assert entry2.errors.of_kind?(:uid, :taken)
  end

  test "should allow same uid across different feeds" do
    feed2 = create(:feed)
    entry1 = create(:feed_entry, feed: feed, uid: "same-uid")
    entry2 = build(:feed_entry, feed: feed2, uid: "same-uid")

    assert entry2.valid?
  end

  test "should belong to feed" do
    entry = valid_feed_entry
    assert_respond_to entry, :feed
    assert_equal feed, entry.feed
  end

  test "should have pending status by default" do
    entry = FeedEntry.new
    assert_equal "pending", entry.status
  end

  test "should have valid enum statuses" do
    entry = valid_feed_entry

    entry.status = :pending
    assert entry.pending?
    assert_equal "pending", entry.status

    entry.status = :processed
    assert entry.processed?
    assert_equal "processed", entry.status
  end

  test "should handle JSONB raw_data" do
    raw_data = { id: "test-id", title: "Test Title", url: "https://example.com/test" }
    entry = create(:feed_entry, raw_data: raw_data)

    saved_entry = FeedEntry.find(entry.id)
    assert_equal raw_data.stringify_keys, saved_entry.raw_data
  end

  test "should allow nil values for optional fields" do
    entry = build(:feed_entry, published_at: nil, raw_data: nil)
    assert entry.valid?
  end

  test "should handle empty uid" do
    entry = build(:feed_entry, uid: "")
    assert_not entry.valid?
    assert entry.errors.of_kind?(:uid, :blank)
  end
end
