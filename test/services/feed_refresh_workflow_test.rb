require "test_helper"

class FeedRefreshWorkflowTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "rss")
  end

  def setup
    stub_freefeed_api_calls
  end

  def stub_freefeed_api_calls
    stub_request(:post, /.*\/v4\/posts/)
      .to_return(
        status: 201,
        body: {
          posts: {
            id: "freefeed_post_#{SecureRandom.hex(8)}",
            body: "Test post",
            createdAt: Time.current.iso8601,
            updatedAt: Time.current.iso8601,
            likes: [],
            comments: []
          }
        }.to_json
      )
  end

  test "#initialize should set feed and stats" do
    workflow = FeedRefreshWorkflow.new(feed)

    assert_equal feed, workflow.feed
    assert_equal({}, workflow.stats)
  end

  test ".workflow_steps should list expected sequence" do
    expected_steps = [
      :initialize_workflow,
      :load_feed_contents,
      :process_feed_contents,
      :filter_new_entries,
      :persist_entries,
      :normalize_entries,
      :persist_posts,
      :publish_posts,
      :finalize_workflow
    ]

    assert_equal expected_steps, FeedRefreshWorkflow.workflow_steps
  end

  test "#step_durations should expose timing information" do
    workflow = FeedRefreshWorkflow.new(feed)

    assert_equal({}, workflow.step_durations)
    assert_equal 0.0, workflow.total_duration
    assert_nil workflow.current_step
  end

  test "#execute should process real RSS data and create posts" do
    # Create feed with proper configuration
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

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

    assert_equal 2, result.length, "Should return 2 posts"

    published_posts = result.select(&:published?)
    assert_equal 2, published_posts.length, "Should have 2 published posts"

    # Posts are ordered by published_at, so second entry comes first
    first_post = published_posts.first
    assert_equal test_feed, first_post.feed
    assert_not_nil first_post.feed_entry
    assert_match(/Another test entry/, first_post.content)
    assert_equal "https://example.com/entry-456", first_post.source_url
    assert_equal "published", first_post.status
    assert_not_nil first_post.freefeed_post_id

    assert_equal 2, FeedEntry.where(feed: test_feed).count
    entries = FeedEntry.where(feed: test_feed)
    assert_equal ["entry-123", "entry-456"], entries.pluck(:uid).sort

    assert_equal 2, Post.where(feed: test_feed, status: :published).count
    assert workflow.stats[:started_at]
    assert workflow.stats[:content_size] > 0
    assert_equal 2, workflow.stats[:total_entries]
    assert_equal 2, workflow.stats[:new_entries]
    assert_equal 2, workflow.stats[:new_posts]
    assert workflow.stats[:completed_at]
    assert workflow.stats[:total_duration] >= 0

    # Verify stats event was created
    events = Event.where(subject: test_feed, type: "feed_refresh")
    assert_equal 1, events.count
    assert_equal 2, events.first.metadata["stats"]["new_posts"]
  end

  test "#execute should skip duplicate entries on subsequent runs" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    # Create existing entry and mark it as imported
    create(:feed_entry, feed: test_feed, uid: "existing-entry-123")
    create(:feed_entry_uid, feed: test_feed, uid: "existing-entry-123")

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

    # Should have 2 feed entry UIDs total (1 existing + 1 new)
    assert_equal 2, FeedEntryUid.where(feed: test_feed).count

    # Should only create 1 new post
    assert_equal 1, Post.where(feed: test_feed).count

    # Verify stats reflect only new entries
    assert_equal 2, workflow.stats[:total_entries]
    assert_equal 1, workflow.stats[:new_entries]
    assert_equal 1, workflow.stats[:new_posts]
  end

  test "#execute should handle HTTP loading errors gracefully" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

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
    assert_match(/Feed.*refresh failed/, EventDescriptionComponent.new(event: error_event).call)
    assert_equal "StandardError", error_event.metadata["error"]["class"]
  end

  test "#execute should handle RSS processing errors gracefully" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    workflow = FeedRefreshWorkflow.new(test_feed)

    # Return invalid RSS that will cause parsing errors
    invalid_rss = "<invalid>not valid RSS</malformed>"

    WebMock.stub_request(:get, test_feed.url).to_return(body: invalid_rss, status: 200)

    # RSS processor raises error for invalid RSS, workflow should handle it
    assert_raises(Feedjira::NoParserAvailable) do
      workflow.execute
    end

    # Verify no entries or posts were created
    assert_equal 0, FeedEntry.where(feed: test_feed).count
    assert_equal 0, Post.where(feed: test_feed).count

    # Verify error event was created
    error_events = Event.where(subject: test_feed, type: "feed_refresh_error")
    assert_equal 1, error_events.count

    error_event = error_events.first
    assert_equal "error", error_event.level
    assert_match(/Feed.*refresh failed/, EventDescriptionComponent.new(event: error_event).call)
    assert_equal "Feedjira::NoParserAvailable", error_event.metadata["error"]["class"]
  end

  test "#execute should handle normalization errors gracefully" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

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
    assert_match(/Feed.*refresh failed/, EventDescriptionComponent.new(event: error_event).call)
  end

  test "#execute should handle database errors during entry persistence" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

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
      assert_match(/Feed.*refresh failed/, EventDescriptionComponent.new(event: error_event).call)
      assert_equal "ActiveRecord::StatementInvalid", error_event.metadata["error"]["class"]
    end
  end

  test "#execute should handle empty feed content gracefully" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

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
    events = Event.where(subject: test_feed, type: "feed_refresh")
    assert_equal 1, events.count
  end

  test "#records should create feed metrics when posts are imported" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>entry-1</guid>
            <title>Entry 1</title>
            <description>Test entry</description>
            <link>https://example.com/entry-1</link>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
          <item>
            <guid>entry-2</guid>
            <title>Entry 2</title>
            <description>Another entry</description>
            <link>https://example.com/entry-2</link>
            <pubDate>#{2.hours.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, test_feed.url).to_return(body: sample_rss, status: 200)

    freeze_time do
      workflow = FeedRefreshWorkflow.new(test_feed)
      workflow.execute

      metric = FeedMetric.find_by(feed: test_feed, date: Date.current)
      assert_not_nil metric
      assert_equal 2, metric.posts_count
      assert_equal 0, metric.invalid_posts_count
    end
  end

  test "#execute should create feed metrics with invalid posts" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    # Create RSS with one valid and one invalid entry (missing link)
    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>valid-entry</guid>
            <title>Valid Entry</title>
            <description>This is valid</description>
            <link>https://example.com/valid</link>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
          <item>
            <guid>invalid-entry</guid>
            <title>Invalid Entry</title>
            <description>Missing link</description>
            <pubDate>#{2.hours.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, test_feed.url).to_return(body: sample_rss, status: 200)

    freeze_time do
      workflow = FeedRefreshWorkflow.new(test_feed)
      workflow.execute

      metric = FeedMetric.find_by(feed: test_feed, date: Date.current)
      assert_not_nil metric
      assert_equal 1, metric.posts_count
      assert_equal 1, metric.invalid_posts_count
    end
  end

  test "#execute should skip metrics when no posts are imported" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    empty_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Empty Feed</title>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    freeze_time do
      workflow = FeedRefreshWorkflow.new(test_feed)
      workflow.execute

      metric = FeedMetric.find_by(feed: test_feed, date: Date.current)
      assert_nil metric, "Should not create metric record for empty feed"
    end
  end

  test "#execute should aggregate feed metrics for multiple refreshes on same day" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    first_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>entry-1</guid>
            <title>Entry 1</title>
            <description>Test entry</description>
            <link>https://example.com/entry-1</link>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    second_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>entry-1</guid>
            <title>Entry 1</title>
            <description>Test entry</description>
            <link>https://example.com/entry-1</link>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
          <item>
            <guid>entry-2</guid>
            <title>Entry 2</title>
            <description>Another entry</description>
            <link>https://example.com/entry-2</link>
            <pubDate>#{2.hours.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    freeze_time do
      # First refresh with 1 post
      WebMock.stub_request(:get, test_feed.url).to_return(body: first_rss, status: 200)
      workflow1 = FeedRefreshWorkflow.new(test_feed)
      workflow1.execute

      metric = FeedMetric.find_by(feed: test_feed, date: Date.current)
      assert_equal 1, metric.posts_count

      # Second refresh with 1 new post (entry-2)
      WebMock.stub_request(:get, test_feed.url).to_return(body: second_rss, status: 200)
      workflow2 = FeedRefreshWorkflow.new(test_feed)
      workflow2.execute

      metric.reload
      assert_equal 1, metric.posts_count, "Metric should reflect only new posts from second refresh"
    end
  end
end
