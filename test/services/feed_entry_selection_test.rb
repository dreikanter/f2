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
    assert_equal({ collapsed_duplicate_uids: 1, known_entries: 1, entries_before_threshold: 1, selected_entries: 1 }, selection.stats)
  end

  test "#call should select the first usable identity before applying the final limit" do
    feed = create(:feed, feed_profile_key: "llm", params: { "prompt" => "Stories", "max_items" => 1 })
    blank = FeedEntry.new(feed: feed, uid: "same", raw_data: { "source_url" => nil, "body" => "" })
    valid = FeedEntry.new(feed: feed, uid: "same", raw_data: { "source_url" => nil, "body" => "Story" })
    extra = FeedEntry.new(feed: feed, uid: "extra", raw_data: { "source_url" => nil, "body" => "Another" })
    selection = FeedEntrySelection.new(feed)

    assert_equal [valid], selection.call([blank, valid, extra])
    assert_equal 1, selection.stats[:rejected_posts]
    assert_equal 1, selection.stats[:overflow_entries]
    assert_equal "Story", selection.posts.fetch("same").content
    assert_not selection.posts.key?("extra")
    assert_empty FeedEntryUid.where(feed: feed)
  end
end
