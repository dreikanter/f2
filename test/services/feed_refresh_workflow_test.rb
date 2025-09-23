require "test_helper"

class FeedRefreshWorkflowTest < ActiveSupport::TestCase
  def feed
    @feed ||= begin
      profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
      create(:feed, feed_profile: profile)
    end
  end

  test "initializes workflow with feed and stats" do
    workflow = FeedRefreshWorkflow.new(feed)

    assert_equal feed, workflow.feed
    assert_equal({}, workflow.stats)
  end

  test "workflow has correct step sequence defined" do
    expected_steps = [
      :initialize_workflow,
      :load_feed_contents,
      :process_feed_contents,
      :filter_new_entries,
      :persist_entries,
      :normalize_entries,
      :persist_posts,
      :finalize_workflow
    ]

    assert_equal expected_steps, FeedRefreshWorkflow.workflow_steps
  end

  test "provides access to timing information" do
    workflow = FeedRefreshWorkflow.new(feed)

    assert_equal({}, workflow.step_durations)
    assert_equal 0.0, workflow.total_duration
    assert_nil workflow.current_step
  end

  test "executes complete workflow with real RSS data and creates valid posts" do
    # Create feed with proper configuration
    profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile: profile)

    workflow = FeedRefreshWorkflow.new(test_feed)

    # Create real RSS content
    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>Test RSS Feed</description>
          <item>
            <guid>entry-123</guid>
            <title>First Test Entry</title>
            <description>This is a test entry description</description>
            <link>https://example.com/entry-123</link>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
          <item>
            <guid>entry-456</guid>
            <title>Second Test Entry</title>
            <description>Another test entry</description>
            <link>https://example.com/entry-456</link>
            <pubDate>#{2.hours.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    # Use real HTTP loader with stubbed network call
    WebMock.stub_request(:get, test_feed.url).to_return(body: sample_rss, status: 200)

    result = workflow.execute

    # Verify workflow completed successfully
    assert_equal 2, result.length, "Should return 2 posts"

    # Verify posts were created properly
    posts = result.select(&:enqueued?)
    assert_equal 2, posts.length, "Should have 2 enqueued posts"

    # Verify post attributes
    first_post = posts.first
    assert_equal test_feed, first_post.feed
    assert_not_nil first_post.feed_entry
    assert_match(/test entry description/, first_post.content)
    assert_equal "https://example.com/entry-123", first_post.source_url
    assert_equal "enqueued", first_post.status

    # Verify feed entries were created
    assert_equal 2, FeedEntry.where(feed: test_feed).count
    entries = FeedEntry.where(feed: test_feed).order(:created_at)
    assert_equal ["entry-123", "entry-456"], entries.pluck(:uid)

    # Verify posts were persisted to database
    assert_equal 2, Post.where(feed: test_feed, status: :published).count

    # Verify workflow stats were recorded
    assert workflow.stats[:started_at]
    assert workflow.stats[:content_size] > 0
    assert_equal 2, workflow.stats[:total_entries]
    assert_equal 2, workflow.stats[:new_entries]
    assert_equal 2, workflow.stats[:new_posts]
    assert workflow.stats[:completed_at]
    assert workflow.stats[:total_duration] >= 0

    # Verify stats event was created
    events = Event.where(subject: test_feed, type: "feed_refresh_stats")
    assert_equal 1, events.count
    assert_equal 2, events.first.metadata["stats"]["new_posts"]
  end

  test "handles duplicate entries correctly on subsequent runs" do
    profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile: profile)

    # Create existing entry
    create(:feed_entry, feed: test_feed, uid: "existing-entry-123")

    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <guid>existing-entry-123</guid>
            <title>Existing Entry</title>
            <description>This entry already exists</description>
            <link>https://example.com/existing</link>
            <pubDate>#{2.hours.ago.rfc822}</pubDate>
          </item>
          <item>
            <guid>new-entry-456</guid>
            <title>New Entry</title>
            <description>This is a new entry</description>
            <link>https://example.com/new</link>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, test_feed.url).to_return(body: sample_rss, status: 200)

    workflow = FeedRefreshWorkflow.new(test_feed)
    result = workflow.execute

    # Should only process the new entry
    assert_equal 1, result.length
    assert_match(/new entry/, result.first.content.downcase)

    # Should have 2 feed entries total (1 existing + 1 new)
    assert_equal 2, FeedEntry.where(feed: test_feed).count

    # Should only create 1 new post
    assert_equal 1, Post.where(feed: test_feed).count

    # Verify stats reflect only new entries
    assert_equal 2, workflow.stats[:total_entries]
    assert_equal 1, workflow.stats[:new_entries]
    assert_equal 1, workflow.stats[:new_posts]
  end

  test "handles HTTP loading errors gracefully" do
    profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile: profile)

    workflow = FeedRefreshWorkflow.new(test_feed)

    # Stub network request to timeout
    WebMock.stub_request(:get, test_feed.url).to_timeout

    error = assert_raises(StandardError) do
      workflow.execute
    end

    assert_match(/execution expired/, error.message)

    # Verify error stats were recorded
    assert workflow.stats[:started_at]
    assert_equal :load_feed_contents, workflow.stats[:failed_at_step]

    # Verify error event was created
    events = Event.where(subject: test_feed, type: "feed_refresh_error")
    assert_equal 1, events.count
    error_event = events.first
    assert_equal "error", error_event.level
    assert_match(/Feed refresh failed at load_feed_contents/, error_event.message)
    assert_equal "StandardError", error_event.metadata["error"]["class"]
  end

  test "handles RSS processing errors gracefully" do
    profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile: profile)

    workflow = FeedRefreshWorkflow.new(test_feed)

    # Return invalid RSS that will cause parsing errors
    invalid_rss = "<invalid>not valid RSS</malformed>"

    WebMock.stub_request(:get, test_feed.url).to_return(body: invalid_rss, status: 200)

    # RSS processor returns empty array for invalid RSS, so workflow should complete
    result = workflow.execute

    # Should complete with no posts due to invalid RSS
    assert_equal 0, result.length
    assert_equal 0, FeedEntry.where(feed: test_feed).count
    assert_equal 0, Post.where(feed: test_feed).count

    # Verify stats show no entries processed
    assert workflow.stats[:started_at]
    assert_equal 0, workflow.stats[:total_entries]
    assert workflow.stats[:completed_at]

    # Should still create event
    events = Event.where(subject: test_feed, type: "feed_refresh_stats")
    assert_equal 1, events.count
  end

  test "handles normalization errors gracefully" do
    profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile: profile)

    workflow = FeedRefreshWorkflow.new(test_feed)

    # Valid RSS that will create entries
    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>test-entry</guid>
            <title>Test Entry</title>
            <description>Test description</description>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, test_feed.url).to_return(body: sample_rss, status: 200)

    # Override normalizer_instance to pass nil instead of the feed_entry
    test_feed.define_singleton_method(:normalizer_instance) do |feed_entry|
      normalizer_class.new(nil)  # Pass nil instead of feed_entry to trigger error
    end

    error = assert_raises(StandardError) do
      workflow.execute
    end

    # Should fail during normalize step
    assert_equal :normalize_entries, workflow.stats[:failed_at_step]

    # Entry should still be created even though normalization failed
    assert_equal 1, FeedEntry.where(feed: test_feed).count

    # Verify error event was created
    events = Event.where(subject: test_feed, type: "feed_refresh_error")
    assert_equal 1, events.count
    error_event = events.first
    assert_match(/Feed refresh failed at normalize_entries/, error_event.message)
  end

  test "handles database errors during entry persistence" do
    profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile: profile)

    workflow = FeedRefreshWorkflow.new(test_feed)

    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>test-entry</guid>
            <title>Test Entry</title>
            <description>Test description</description>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, test_feed.url).to_return(body: sample_rss, status: 200)

    # Mock FeedEntry.insert_all to fail
    FeedEntry.stub(:insert_all, proc { raise ActiveRecord::StatementInvalid.new("Database error") }) do
      error = assert_raises(ActiveRecord::StatementInvalid) do
        workflow.execute
      end

      assert_equal "Database error", error.message

      # Should fail during persist_entries step
      assert_equal :persist_entries, workflow.stats[:failed_at_step]

      # Verify error event was created
      events = Event.where(subject: test_feed, type: "feed_refresh_error")
      assert_equal 1, events.count
      error_event = events.first
      assert_match(/Feed refresh failed at persist_entries/, error_event.message)
      assert_equal "ActiveRecord::StatementInvalid", error_event.metadata["error"]["class"]
    end
  end

  test "handles empty feed content gracefully" do
    profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile: profile)

    workflow = FeedRefreshWorkflow.new(test_feed)

    # Empty RSS with no items
    empty_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Empty Feed</title>
          <description>No items</description>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    result = workflow.execute

    # Should complete successfully with no posts
    assert_equal 0, result.length
    assert_equal 0, FeedEntry.where(feed: test_feed).count
    assert_equal 0, Post.where(feed: test_feed).count

    # Verify stats show empty processing
    assert workflow.stats[:total_entries] == 0 || workflow.stats[:total_entries].nil?
    assert workflow.stats[:new_entries] == 0 || workflow.stats[:new_entries].nil?
    assert workflow.stats[:new_posts] == 0 || workflow.stats[:new_posts].nil?

    # Should still create success event
    events = Event.where(subject: test_feed, type: "feed_refresh_stats")
    assert_equal 1, events.count
  end
end
