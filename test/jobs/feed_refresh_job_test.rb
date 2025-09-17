require "test_helper"
require "minitest/mock"

class FeedRefreshJobTest < ActiveJob::TestCase
  def feed
    @feed ||= create(:feed, loader: "http", processor: "rss", normalizer: "rss")
  end

  test "handles missing feed gracefully" do
    assert_logs_match(/Feed -1 not found/) do
      FeedRefreshJob.perform_now(-1)
    end
  end

  test "handles unknown loader gracefully" do
    bad_feed = create(:feed, loader: "unknown", processor: "rss", normalizer: "rss")

    assert_raises(ArgumentError, "Unknown loader: unknown") do
      FeedRefreshJob.perform_now(bad_feed.id)
    end
  end

  test "handles unknown processor gracefully" do
    bad_feed = create(:feed, loader: "http", processor: "unknown", normalizer: "rss")

    assert_raises(ArgumentError, "Unknown processor: unknown") do
      FeedRefreshJob.perform_now(bad_feed.id)
    end
  end

  test "handles unknown normalizer gracefully" do
    bad_feed = create(:feed, loader: "http", processor: "rss", normalizer: "unknown")

    assert_raises(ArgumentError, "Unknown normalizer: unknown") do
      FeedRefreshJob.perform_now(bad_feed.id)
    end
  end

  test "persist_feed_entries creates new entries and skips duplicates" do
    job = FeedRefreshJob.new

    processed_entries = [
      { uid: "entry-1", published_at: Time.current, raw_data: { "title" => "First" } },
      { uid: "entry-2", published_at: Time.current, raw_data: { "title" => "Second" } }
    ]

    # First run should create both entries
    new_entries = job.send(:persist_feed_entries, feed, processed_entries)
    assert_equal 2, new_entries.count
    assert_equal ["entry-1", "entry-2"], new_entries.map(&:uid).sort

    # Verify entries were created
    assert_equal 2, FeedEntry.where(feed: feed).count

    # Second run with same entries should create none (skip duplicates)
    new_entries = job.send(:persist_feed_entries, feed, processed_entries)
    assert_equal 0, new_entries.count

    # Total should still be 2
    assert_equal 2, FeedEntry.where(feed: feed).count
  end

  test "persist_feed_entries maintains order" do
    job = FeedRefreshJob.new

    processed_entries = [
      { uid: "first", published_at: 2.hours.ago, raw_data: {} },
      { uid: "second", published_at: 1.hour.ago, raw_data: {} },
      { uid: "third", published_at: Time.current, raw_data: {} }
    ]

    new_entries = job.send(:persist_feed_entries, feed, processed_entries)

    assert_equal ["first", "second", "third"], new_entries.map(&:uid)

    # Database entries should maintain creation order
    entries = FeedEntry.where(feed: feed).order(:created_at)
    assert_equal ["first", "second", "third"], entries.pluck(:uid)
  end

  test "normalize_single_entry handles successful normalization" do
    job = FeedRefreshJob.new
    entry = create(:feed_entry, feed: feed, uid: "test-entry", status: :pending)

    # Mock the normalizer instance
    mock_normalizer = Minitest::Mock.new
    mock_post = build(:post, feed: feed, feed_entry: entry, status: :enqueued)
    mock_post.save!
    mock_normalizer.expect(:normalize, mock_post)

    # Mock the feed's normalizer_instance method
    feed.stub(:normalizer_instance, mock_normalizer) do
      result = job.send(:normalize_single_entry, entry, feed)

      assert_equal "processed", entry.reload.status
      assert_equal true, result[:valid]
      assert_equal 1, Post.where(feed_entry: entry).count
    end

    mock_normalizer.verify
  end

  test "normalize_single_entry handles rejected posts" do
    job = FeedRefreshJob.new
    entry = create(:feed_entry, feed: feed, uid: "test-entry", status: :pending)

    # Mock the normalizer instance
    mock_normalizer = Minitest::Mock.new
    mock_post = build(:post, feed: feed, feed_entry: entry, status: :rejected)
    mock_post.save!
    mock_normalizer.expect(:normalize, mock_post)

    # Mock the feed's normalizer_instance method
    feed.stub(:normalizer_instance, mock_normalizer) do
      result = job.send(:normalize_single_entry, entry, feed)

      assert_equal "processed", entry.reload.status
      assert_equal false, result[:valid]
    end

    mock_normalizer.verify
  end

  test "normalize_single_entry handles errors gracefully" do
    job = FeedRefreshJob.new
    entry = create(:feed_entry, feed: feed, uid: "test-entry", status: :pending)

    # Mock the normalizer instance to raise an error
    mock_normalizer = Minitest::Mock.new
    mock_normalizer.expect(:normalize, nil) { raise StandardError, "Normalization failed" }

    # Mock the feed's normalizer_instance method
    feed.stub(:normalizer_instance, mock_normalizer) do
      assert_logs_match(/Failed to normalize feed entry/) do
        result = job.send(:normalize_single_entry, entry, feed)

        assert_equal "processed", entry.reload.status
        assert_equal false, result[:valid]
      end
    end

    mock_normalizer.verify
  end

  private

  def assert_logs_match(pattern)
    original_logger = Rails.logger
    log_output = StringIO.new
    Rails.logger = Logger.new(log_output)

    yield

    assert_match pattern, log_output.string
  ensure
    Rails.logger = original_logger
  end
end
