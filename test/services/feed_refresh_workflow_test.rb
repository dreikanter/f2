require "test_helper"

class FeedRefreshWorkflowTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, loader: "http", processor: "rss", normalizer: "rss")
  end

  test "persist_entries creates new entries and skips duplicates" do
    workflow = FeedRefreshWorkflow.new(feed)

    processed_entries = [
      {
        uid: "entry-1",
        published_at: Time.current,
        raw_data: { "title" => "First" }
      },
      {
        uid: "entry-2",
        published_at: Time.current,
        raw_data: { "title" => "Second" }
      }
    ]

    filtered_entries = workflow.send(:filter_new_entries, processed_entries)
    new_entries = workflow.send(:persist_entries, filtered_entries)
    assert_equal 2, new_entries.count
    assert_equal ["entry-1", "entry-2"], new_entries.map(&:uid).sort

    assert_equal 2, FeedEntry.where(feed: feed).count

    filtered_entries = workflow.send(:filter_new_entries, processed_entries)
    new_entries = workflow.send(:persist_entries, filtered_entries)
    assert_equal 0, new_entries.count

    assert_equal 2, FeedEntry.where(feed: feed).count
  end

  test "persist_entries maintains order" do
    workflow = FeedRefreshWorkflow.new(feed)

    processed_entries = [
      {
        uid: "first",
        published_at: 2.hours.ago,
        raw_data: {}
      },
      {
        uid: "second",
        published_at: 1.hour.ago,
        raw_data: {}
      },
      {
        uid: "third",
        published_at: Time.current,
        raw_data: {}
      }
    ]

    new_entries = workflow.send(:persist_entries, processed_entries)

    assert_equal ["first", "second", "third"], new_entries.map(&:uid)

    # Database entries should maintain creation order
    entries = FeedEntry.where(feed: feed).order(:created_at)
    assert_equal ["first", "second", "third"], entries.pluck(:uid)
  end

  test "normalize_entries returns posts for each entry" do
    workflow = FeedRefreshWorkflow.new(feed)

    entry1 = create(:feed_entry, feed: feed, uid: "entry-1")
    entry2 = create(:feed_entry, feed: feed, uid: "entry-2")
    new_entries = [entry1, entry2]

    # Mock the normalizer instance
    mock_normalizer = Minitest::Mock.new
    mock_post1 = build(:post, feed: feed, feed_entry: entry1, status: :draft)
    mock_post2 = build(:post, feed: feed, feed_entry: entry2, status: :rejected)

    mock_normalizer.expect(:normalize, mock_post1, [entry1])
    mock_normalizer.expect(:normalize, mock_post2, [entry2])

    # Mock the feed's normalizer_instance method
    feed.stub(:normalizer_instance, mock_normalizer) do
      posts = workflow.send(:normalize_entries, new_entries)

      assert_equal 2, posts.length
      assert_equal [entry1, entry2], posts.map(&:feed_entry)
      assert_equal ["draft", "rejected"], posts.map(&:status)
    end

    mock_normalizer.verify
  end

  test "persist_posts saves posts with draft status" do
    workflow = FeedRefreshWorkflow.new(feed)

    entry1 = create(:feed_entry, feed: feed, uid: "entry-1")
    entry2 = create(:feed_entry, feed: feed, uid: "entry-2")

    post1 = build(:post, feed: feed, feed_entry: entry1, status: :draft, uid: "post-1", source_url: "https://example.com/1", content: "Content 1", published_at: Time.current)
    post2 = build(:post, feed: feed, feed_entry: entry2, status: :rejected, uid: "post-2", source_url: "https://example.com/2", content: "Content 2", published_at: Time.current)
    posts = [post1, post2]

    result = workflow.send(:persist_posts, posts)

    assert_equal posts, result
    assert_equal 1, Post.where(status: :published).count  # draft posts become published
    assert_equal 0, Post.where(status: :rejected).count   # rejected posts are not persisted
    assert_equal 1, Post.count  # only draft posts are saved
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
