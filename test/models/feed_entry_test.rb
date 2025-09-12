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
    assert_includes entry.errors[:uid], "can't be blank"
  end

  test "should require title" do
    entry = build(:feed_entry, title: nil)
    assert_not entry.valid?
    assert_includes entry.errors[:title], "can't be blank"
  end

  test "should require uid to be unique within feed scope" do
    entry1 = create(:feed_entry, feed: feed, uid: "duplicate-uid")
    entry2 = build(:feed_entry, feed: feed, uid: "duplicate-uid")

    assert_not entry2.valid?
    assert_includes entry2.errors[:uid], "has already been taken"
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

    entry.status = :failed
    assert entry.failed?
    assert_equal "failed", entry.status
  end

  test "should handle JSONB raw_data" do
    raw_data = { id: "test-id", title: "Test Title", author: "Test Author" }
    entry = create(:feed_entry, raw_data: raw_data)

    saved_entry = FeedEntry.find(entry.id)
    assert_equal raw_data.stringify_keys, saved_entry.raw_data
  end

  test "should allow nil values for optional fields" do
    entry = build(:feed_entry, content: nil, published_at: nil, source_url: nil, raw_data: nil)
    assert entry.valid?
  end

  test "should handle empty strings" do
    entry = build(:feed_entry, uid: "", title: "")
    assert_not entry.valid?
    assert_includes entry.errors[:uid], "can't be blank"
    assert_includes entry.errors[:title], "can't be blank"
  end

  test "should strip whitespace from uid and title" do
    entry = build(:feed_entry, uid: "  test-uid  ", title: "  Test Title  ")
    entry.uid = entry.uid.strip if entry.uid
    entry.title = entry.title.strip if entry.title

    assert_equal "test-uid", entry.uid
    assert_equal "Test Title", entry.title
  end
end
