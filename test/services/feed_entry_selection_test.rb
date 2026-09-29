require "test_helper"

class FeedEntrySelectionTest < ActiveSupport::TestCase
  test "#call should use saved history with current temporary feed settings" do
    saved = create(:feed)
    create(:feed_entry_uid, feed: saved, uid: "known")
    current = Feed.new(import_after: Time.current)
    known = FeedEntry.new(uid: "known")
    unknown_date = FeedEntry.new(uid: "undated")
    old = FeedEntry.new(uid: "old", published_at: current.import_after)
    selection = FeedEntrySelection.new(current, history_feed: saved)

    assert_equal [unknown_date], selection.call([known, old, unknown_date, unknown_date])
    assert_equal({ collapsed_duplicate_uids: 1, known_entries: 1, entries_before_threshold: 1 }, selection.stats)
  end
end
