require "test_helper"

class FeedRefreshWorkflowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  def empty_rss
    <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"><channel><title>Empty</title></channel></rss>
    RSS
  end

  test "#initialize should set feed and stats" do
    workflow = FeedRefreshWorkflow.new(feed)

    assert_equal feed, workflow.feed
    assert_equal({}, workflow.stats)
  end

  test ".workflow_steps should list expected sequence" do
    expected_steps = [
      :interrupt_abandoned_refresh_events,
      :initialize_workflow,
      :load_feed_contents,
      :process_feed_contents,
      :filter_new_entries,
      :persist_entries,
      :normalize_entries,
      :persist_posts,
      :enqueue_publication,
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
    test_feed = create(:feed, :enabled, url: "https://example.com/feed.xml", feed_profile_key: "rss")

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
            <description>Тестовое содержимое</description>
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

    result = perform_enqueued_jobs { workflow.execute }

    assert_equal 2, result.length, "Should return 2 posts"

    # Publishing is async now; the chain runs within perform_enqueued_jobs.
    published_posts = test_feed.posts.where(status: :published).order(:published_at)
    assert_equal 2, published_posts.count, "Should have 2 published posts"

    # Posts are published in published_at order, so the older entry comes first
    first_post = published_posts.first
    assert_equal test_feed, first_post.feed
    assert_not_nil first_post.feed_entry
    assert_match(/Another test entry/, first_post.content)
    assert_equal "https://example.com/entry-456", first_post.source_url
    assert_not_nil first_post.freefeed_post_id

    assert_equal 2, FeedEntry.where(feed: test_feed).count
    entries = FeedEntry.where(feed: test_feed)
    assert_equal ["entry-123", "entry-456"], entries.pluck(:uid).sort

    assert_equal 2, Post.where(feed: test_feed, status: :published).count
    assert workflow.stats[:started_at]
    assert_equal sample_rss.bytesize, workflow.stats[:content_size]
    assert_equal 2, workflow.stats[:total_entries]
    assert_equal 2, workflow.stats[:new_entries]
    assert_equal 2, workflow.stats[:new_posts]
    assert workflow.stats[:completed_at]
    assert workflow.stats[:total_duration] >= 0

    # Verify stats event was created and promoted to a user-visible level
    events = Event.where(subject: test_feed, type: "feed_refresh")
    assert_equal 1, events.count
    assert_equal "completed", events.first.metadata["status"]
    assert_equal "info", events.first.level
    assert_equal 2, events.first.metadata["stats"]["new_posts"]

    # Verify each new post is referenced by the refresh event
    references = events.first.event_references
    assert_equal 2, references.count
    assert_equal Post.where(feed: test_feed).order(:id).pluck(:id),
                 references.where(reference_type: "Post").order(:reference_id).pluck(:reference_id).sort
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

  test "#execute should skip entries published at or before the import threshold" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss", import_after: 3.hours.ago)

    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <guid>old-entry</guid>
            <title>Old Entry</title>
            <description>Published before the threshold</description>
            <link>https://example.com/old</link>
            <pubDate>#{5.hours.ago.rfc822}</pubDate>
          </item>
          <item>
            <guid>fresh-entry</guid>
            <title>Fresh Entry</title>
            <description>Published after the threshold</description>
            <link>https://example.com/fresh</link>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, test_feed.url).to_return(body: sample_rss, status: 200)

    workflow = FeedRefreshWorkflow.new(test_feed)
    result = workflow.execute

    assert_equal 1, result.length
    assert_equal ["fresh-entry"], FeedEntry.where(feed: test_feed).pluck(:uid)

    # Skipped entries leave no UID record, so they can still import later
    # if the threshold is cleared.
    assert_equal ["fresh-entry"], FeedEntryUid.where(feed: test_feed).pluck(:uid)

    assert_equal 2, workflow.stats[:total_entries]
    assert_equal 1, workflow.stats[:new_entries]
    assert_equal 1, workflow.stats[:entries_before_threshold]
  end

  test "#filter_new_entries should collapse duplicate uids within the batch" do
    test_feed = create(:feed)
    workflow = FeedRefreshWorkflow.new(test_feed)

    first = FeedEntry.new(feed: test_feed, uid: "dup", published_at: 1.hour.ago)
    second = FeedEntry.new(feed: test_feed, uid: "dup", published_at: 2.hours.ago)
    unique = FeedEntry.new(feed: test_feed, uid: "unique", published_at: 1.hour.ago)

    result = workflow.send(:filter_new_entries, [first, second, unique])

    assert_equal ["dup", "unique"], result.map(&:uid)
    assert_same first, result.first
    assert_equal 1, workflow.stats[:collapsed_duplicate_uids]
  end

  test "#filter_new_entries should not record collapsed count without duplicates" do
    test_feed = create(:feed)
    workflow = FeedRefreshWorkflow.new(test_feed)

    entries = [
      FeedEntry.new(feed: test_feed, uid: "a", published_at: 1.hour.ago),
      FeedEntry.new(feed: test_feed, uid: "b", published_at: 1.hour.ago)
    ]

    workflow.send(:filter_new_entries, entries)

    assert_nil workflow.stats[:collapsed_duplicate_uids]
  end

  test "#filter_new_entries should keep entries without a published date despite the import threshold" do
    test_feed = create(:feed, import_after: 1.hour.ago)
    workflow = FeedRefreshWorkflow.new(test_feed)

    undated_entry = FeedEntry.new(feed: test_feed, uid: "undated-entry", published_at: nil)
    stale_entry = FeedEntry.new(feed: test_feed, uid: "old-entry", published_at: 2.hours.ago)

    result = workflow.send(:filter_new_entries, [undated_entry, stale_entry])

    assert_equal ["undated-entry"], result.map(&:uid)
    assert_equal 1, workflow.stats[:entries_before_threshold]
  end

  test "#execute should reject image-less posts when the feed is images-only" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss", images_only: true)

    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <guid>with-image</guid>
            <title>Has an image</title>
            <description>This entry ships an image</description>
            <link>https://example.com/with-image</link>
            <enclosure url="https://example.com/photo.jpg" type="image/jpeg" length="1000"/>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
          <item>
            <guid>without-image</guid>
            <title>No image here</title>
            <description>This entry has only text</description>
            <link>https://example.com/without-image</link>
            <pubDate>#{2.hours.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, test_feed.url).to_return(body: sample_rss, status: 200)

    workflow = FeedRefreshWorkflow.new(test_feed)
    workflow.execute

    # Both entries persist as posts; the image-less one is rejected rather than
    # dropped, so its uid stays recorded for normal dedup on later refreshes.
    with_image = Post.find_by(feed: test_feed, uid: "with-image")
    without_image = Post.find_by(feed: test_feed, uid: "without-image")

    assert with_image.enqueued?
    assert without_image.rejected?
    assert_includes without_image.validation_errors, "no_images"

    assert_equal 1, workflow.stats[:new_posts]
    assert_equal 1, workflow.stats[:rejected_posts]
  end

  test "#execute should handle HTTP loading errors gracefully" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    workflow = FeedRefreshWorkflow.new(test_feed)

    # Stub network request to timeout
    WebMock.stub_request(:get, test_feed.url).to_timeout

    error = assert_raises(Loader::Error) do
      workflow.execute
    end

    assert_match(/execution expired/, error.message)

    # Verify error stats were recorded
    assert workflow.stats[:started_at]
    assert_equal :load_feed_contents, workflow.stats[:failed_at_step]
    assert_equal workflow.total_duration, workflow.stats[:total_duration]

    # Verify the started event was updated in place with the failure
    events = Event.where(subject: test_feed, type: "feed_refresh")
    assert_equal 1, events.count
    error_event = events.first
    assert_equal "failed", error_event.metadata["status"]
    assert_equal "error", error_event.level
    assert_match(/execution expired/, error_event.message)
    assert_equal "Loader::Error", error_event.metadata["error"]["class"]
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
    error_events = Event.where(subject: test_feed, type: "feed_refresh")
    assert_equal 1, error_events.count

    error_event = error_events.first
    assert_equal "failed", error_event.metadata["status"]
    assert_equal "error", error_event.level
    assert error_event.message.present?
    assert_equal "Feedjira::NoParserAvailable", error_event.metadata["error"]["class"]
  end

  test "#execute should persist an original item as a publishable null-source post" do
    create(:llm_model, model_id: "gpt-4.1")
    original_user = create(:user)
    credential = create(:ai_credential, :active, user: original_user)
    original_feed = create(:feed, :enabled, feed_profile_key: "llm", user: original_user,
                                          ai_credential: credential, ai_model: "gpt-4.1",
                                          params: { "prompt" => "daily roundup" })

    raw_data = { items: [{ "source_url" => nil, "body" => "Сегодня: A, B, C" }] }.to_json
    stub_ai_response(JSON.parse(raw_data).fetch("items"))
    workflow = FeedRefreshWorkflow.new(original_feed)

    workflow.execute

    assert_equal raw_data.bytesize, workflow.stats[:content_size]

    post = original_feed.posts.last
    assert_not_nil post, "an original item should persist a post"
    assert_nil post.source_url
    assert_match(/\A[0-9a-f-]{36}\z/, post.uid)
    assert_equal "Сегодня: A, B, C", post.content
  end

  test "#execute should not disable an AI credential when an ordinary loader fails" do
    llm_user = create(:user)
    credential = create(:ai_credential, :active, user: llm_user)
    test_feed = create(:feed, feed_profile_key: "rss", user: llm_user, ai_credential: credential)

    workflow = FeedRefreshWorkflow.new(test_feed)
    stub_request(:get, test_feed.url).to_return(status: 500)

    assert_raises(Loader::Error) { workflow.execute }

    assert_predicate credential.reload, :active?
  end

  test "#execute should report only the run's SDK usage even when timestamps overlap" do
    freeze_time
    create(:llm_model, model_id: "gpt-5-nano",
                       pricing: { text_tokens: { standard: { input_per_million: 0.05, output_per_million: 0.4 } } })
    credential = create(:ai_credential, :active)
    test_feed = create(:feed, :enabled, user: credential.user, ai_credential: credential,
                                      feed_profile_key: "llm", ai_model: "gpt-5-nano",
                                      params: { "prompt" => "Daily roundup" })
    preview = create(:llm_chat, user: test_feed.user, feed: test_feed, purpose: :preview)
    create(:ruby_llm_usage, chat: preview, total_cost: 9)
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(body: JSON.parse(file_fixture("llm_transcripts/completed.json").read))

    FeedRefreshWorkflow.new(test_feed).execute

    event = Event.find_by!(subject: test_feed, type: "feed_refresh")
    chat = test_feed.llm_chats.scheduled_run.sole
    assert_equal "completed", event.metadata["status"]
    assert_equal 1, event.metadata.dig("stats", "llm_calls")
    assert_equal 0.001, event.metadata.dig("stats", "llm_cost_cents")
    assert_equal [chat], event.references
    assert_requested request, times: 1
  end

  test "#execute should report retained SDK usage after provider failure" do
    credential = create(:ai_credential, :active)
    test_feed = create(:feed, :enabled, user: credential.user, ai_credential: credential,
                                      feed_profile_key: "llm", ai_model: "gpt-5-nano",
                                      params: { "prompt" => "Daily roundup" })
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(status: 429, body: { error: { message: "Rate limited", type: "rate_limit_error" } })

    assert_raises(Loader::Error) { FeedRefreshWorkflow.new(test_feed).execute }

    event = Event.find_by!(subject: test_feed, type: "feed_refresh")
    chat = test_feed.llm_chats.sole
    assert_equal "failed", event.metadata["status"]
    assert_equal "failed", chat.ruby_llm_usages.sole.status
    assert_equal 1, event.metadata.dig("stats", "llm_calls")
    assert_equal 0, event.metadata.fetch("stats").fetch("llm_cost_cents")
    assert_equal [chat], event.references
    assert_requested request, times: 1
  end

  test "#execute should record no LLM usage stats for a run without LLM calls" do
    test_feed = create(:feed, :enabled, url: "https://example.com/feed.xml", feed_profile_key: "rss")
    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    FeedRefreshWorkflow.new(test_feed).execute

    event = Event.find_by!(subject: test_feed, type: "feed_refresh")

    assert_equal "completed", event.metadata["status"]
    assert_not event.metadata["stats"].key?("llm_calls")
    assert_not event.metadata["stats"].key?("llm_cost_cents")
    assert_empty event.event_references
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

    # Make normalization fail at the collaborator boundary
    normalizer = Object.new
    normalizer.define_singleton_method(:normalize) { raise "normalization failed" }

    test_feed.stub(:normalizer_instance, normalizer) do
      assert_raises(StandardError) { workflow.execute }
    end

    # Should fail during normalize step
    assert_equal :normalize_entries, workflow.stats[:failed_at_step]

    # Entry should still be created even though normalization failed
    assert_equal 1, FeedEntry.where(feed: test_feed).count

    # Verify error event was created
    events = Event.where(subject: test_feed, type: "feed_refresh")
    assert_equal 1, events.count
    error_event = events.first
    assert_equal "failed", error_event.metadata["status"]
    assert error_event.message.present?
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
      events = Event.where(subject: test_feed, type: "feed_refresh")
      assert_equal 1, events.count
      error_event = events.first
      assert_equal "failed", error_event.metadata["status"]
      assert_match(/Database error/, error_event.message)
      assert_equal "ActiveRecord::StatementInvalid", error_event.metadata["error"]["class"]
    end
  end

  test "#execute should advance the refresh time when no posts are found" do
    test_feed = create(:feed, last_successful_refresh_at: 1.day.ago)
    stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    freeze_time do
      FeedRefreshWorkflow.new(test_feed).execute

      assert_equal Time.current, test_feed.reload.last_refreshed_at
      assert_empty test_feed.posts
      assert_empty test_feed.feed_entries
    end
  end

  test "#execute should preserve the last successful refresh time on failure" do
    refreshed_at = 1.day.ago.change(usec: 0)
    test_feed = create(:feed, last_successful_refresh_at: refreshed_at)
    stub_request(:get, test_feed.url).to_return(status: 500)

    assert_raises(Loader::Error) { FeedRefreshWorkflow.new(test_feed).execute }

    assert_equal refreshed_at, test_feed.reload.last_refreshed_at
  end

  test "#execute should handle empty feed content gracefully" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    workflow = FeedRefreshWorkflow.new(test_feed)

    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    # No enqueued posts means the publish chain must not be kicked
    result = nil
    assert_no_enqueued_jobs(only: PostPublishJob) { result = workflow.execute }

    # Should complete successfully with no posts
    assert_equal 0, result.length
    assert_equal 0, FeedEntry.where(feed: test_feed).count
    assert_equal 0, Post.where(feed: test_feed).count
    assert_not_nil test_feed.reload.last_successful_refresh_at

    # Verify stats show empty processing
    assert workflow.stats[:total_entries] == 0 || workflow.stats[:total_entries].nil?
    assert workflow.stats[:new_entries] == 0 || workflow.stats[:new_entries].nil?
    assert workflow.stats[:new_posts] == 0 || workflow.stats[:new_posts].nil?

    # Should still create success event
    events = Event.where(subject: test_feed, type: "feed_refresh")
    assert_equal 1, events.count
  end

  test "#execute should replace the started event with a completed event" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    # A local, because the singleton method's body resolves methods against the
    # loader object, not the test case.
    rss_body = empty_rss

    in_flight_event = nil
    loader = Object.new
    loader.define_singleton_method(:load) do
      in_flight_event = Event.find_by(subject: test_feed, type: "feed_refresh")
      rss_body
    end

    test_feed.stub(:loader_instance, loader) { FeedRefreshWorkflow.new(test_feed).execute }

    assert_not_nil in_flight_event, "the event should exist before loading starts"
    assert_equal "started", in_flight_event.metadata["status"]
    assert_equal "info", in_flight_event.level, "the in-flight record should be user-visible"
    assert in_flight_event.metadata["stats"]["started_at"].present?

    assert_not Event.exists?(in_flight_event.id), "the started event should be deleted on completion"

    events = Event.where(subject: test_feed, type: "feed_refresh")
    assert_equal 1, events.count
    completed_event = events.first
    assert_equal "completed", completed_event.metadata["status"]
    assert_equal "info", completed_event.level
  end

  test "#execute should keep the completed event when a post-completion step fails" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")
    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    FeedMetric.stub(:record, proc { raise ActiveRecord::StatementInvalid.new("Database error") }) do
      assert_raises(ActiveRecord::StatementInvalid) { FeedRefreshWorkflow.new(test_feed).execute }
    end

    event = Event.find_by(subject: test_feed, type: "feed_refresh")
    assert_equal "completed", event.metadata["status"]
    assert_equal "info", event.level
  end

  test "#execute should mark an abandoned started event as interrupted" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    abandoned_started_at = 1.day.ago
    abandoned = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: test_feed,
      user: test_feed.user,
      metadata: { status: "started", stats: { started_at: abandoned_started_at.iso8601 } }
    )

    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    FeedRefreshWorkflow.new(test_feed).execute

    abandoned.reload
    assert_equal "interrupted", abandoned.metadata["status"]
    assert_equal "debug", abandoned.level, "the dead run's record should leave the user event feed"
    assert_equal abandoned_started_at.iso8601, abandoned.metadata.dig("stats", "started_at"),
                 "the rest of the abandoned event's metadata stays intact"
  end

  test "#execute should retain the dead run's LLM cost on its interrupted event" do
    test_feed = create(:feed, :enabled, url: "https://example.com/feed.xml", feed_profile_key: "rss")
    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    abandoned = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: test_feed,
      user: test_feed.user,
      metadata: { status: "started", stats: { started_at: 10.minutes.ago.iso8601 } }
    )
    dead_chat = create(:llm_chat, user: test_feed.user, feed: test_feed, started_at: 9.minutes.ago)
    create(:ruby_llm_usage, chat: dead_chat, total_cost: "0.40")
    abandoned.event_references.create!(reference: dead_chat)

    FeedRefreshWorkflow.new(test_feed).execute

    abandoned.reload
    assert_equal "interrupted", abandoned.metadata["status"]
    assert_equal 1, abandoned.metadata.dig("stats", "llm_calls")
    assert_equal 40, abandoned.metadata.dig("stats", "llm_cost_cents")
    assert_equal [dead_chat], abandoned.references

    completed = Event.where(subject: test_feed, type: "feed_refresh")
                     .where("metadata ->> 'status' = 'completed'").sole
    assert_not completed.metadata["stats"].key?("llm_calls"),
               "the sweeping run must not absorb the dead run's spend"
    assert_empty completed.event_references
  end

  test "#execute should interrupt events using only their linked usage" do
    test_feed = create(:feed, :enabled, url: "https://example.com/feed.xml", feed_profile_key: "rss")
    stub_request(:get, test_feed.url).to_return(body: empty_rss)
    abandoned = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: test_feed,
      user: test_feed.user,
      metadata: { status: "started", stats: { started_at: 10.minutes.ago.iso8601 } }
    )
    linked = create(:llm_chat, user: test_feed.user, feed: test_feed)
    create(:ruby_llm_usage, chat: linked, total_cost: nil)
    reference = abandoned.event_references.create!(reference: linked)
    create(:ruby_llm_usage, chat: create(:llm_chat, user: test_feed.user, feed: test_feed), total_cost: "0.99")

    FeedRefreshWorkflow.new(test_feed).execute

    assert_equal "interrupted", abandoned.reload.metadata["status"]
    assert_equal 1, abandoned.metadata.dig("stats", "llm_calls")
    assert_nil abandoned.metadata.dig("stats", "llm_cost_cents")
    assert_equal [reference.id], abandoned.event_references.pluck(:id)
    assert_equal [linked], abandoned.references
  end

  test "#execute should not attribute unlinked usage to an interrupted event" do
    test_feed = create(:feed, :enabled, url: "https://example.com/feed.xml", feed_profile_key: "rss")
    stub_request(:get, test_feed.url).to_return(body: empty_rss)
    abandoned = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: test_feed,
      user: test_feed.user,
      metadata: { status: "started", stats: { started_at: 10.minutes.ago.iso8601 } }
    )
    create(:ruby_llm_usage, chat: create(:llm_chat, user: test_feed.user, feed: test_feed))

    FeedRefreshWorkflow.new(test_feed).execute

    assert_equal "interrupted", abandoned.reload.metadata["status"]
    assert_not abandoned.metadata.fetch("stats").key?("llm_calls")
    assert_empty abandoned.references
  end

  test "#execute should not touch other feeds' started events" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")
    other_feed = create(:feed)

    other_started = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: other_feed,
      user: other_feed.user,
      metadata: { status: "started" }
    )
    completed = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: test_feed,
      user: test_feed.user,
      metadata: { status: "completed" }
    )

    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    FeedRefreshWorkflow.new(test_feed).execute

    assert_equal "started", other_started.reload.metadata["status"]
    assert_equal "completed", completed.reload.metadata["status"]
  end

  test "#execute should leave a prior failed event untouched and start a new lifecycle" do
    test_feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")

    failed = Event.create!(
      type: "feed_refresh",
      level: :error,
      subject: test_feed,
      user: test_feed.user,
      message: "Connection timeout",
      metadata: { status: "failed" }
    )

    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    FeedRefreshWorkflow.new(test_feed).execute

    assert_equal "failed", failed.reload.metadata["status"]
    assert_equal "error", failed.level

    events = Event.where(subject: test_feed, type: "feed_refresh").order(:id)
    assert_equal 2, events.count
    assert_equal "completed", events.last.metadata["status"]
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

    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    freeze_time do
      workflow = FeedRefreshWorkflow.new(test_feed)
      workflow.execute

      metric = FeedMetric.find_by(feed: test_feed, date: Date.current)
      assert_nil metric, "Should not create metric record for empty feed"
    end
  end

  test "#execute should increment the failure streak on error" do
    test_feed = create(:feed, :enabled, url: "https://example.com/feed.xml", feed_profile_key: "rss")
    WebMock.stub_request(:get, test_feed.url).to_timeout

    assert_raises(Loader::Error) { FeedRefreshWorkflow.new(test_feed).execute }

    assert_equal 1, test_feed.reload.consecutive_failures
    assert test_feed.enabled?
  end

  test "#execute should reset the failure streak after a successful refresh" do
    test_feed = create(:feed, :enabled, url: "https://example.com/feed.xml",
                                         feed_profile_key: "rss", consecutive_failures: 3)
    WebMock.stub_request(:get, test_feed.url).to_return(body: empty_rss, status: 200)

    FeedRefreshWorkflow.new(test_feed).execute

    assert_equal 0, test_feed.reload.consecutive_failures
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

  def ai_feed_with_schedule
    user = create(:user)
    credential = create(:ai_credential, :active, user: user)
    feed = create(:feed, :enabled, feed_profile_key: "llm", user: user,
                                   ai_credential: credential, ai_model: "gpt-4.1",
                                   params: { "prompt" => "daily roundup" })
    create(:feed_schedule, feed: feed)
    feed
  end

  def stub_ai_response(items)
    response = JSON.parse(file_fixture("llm_transcripts/completed.json").read)
    response["model"] = "gpt-4.1"
    response["output"].last["content"].first["text"] = { items: items }.to_json
    stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)
  end

  test "#execute should reject an over-limit response before persisting entries or posts" do
    create(:llm_model, model_id: "gpt-4.1")
    feed = ai_feed_with_schedule
    feed.update!(params: feed.params.merge("max_items" => 1))
    request = stub_ai_response([
      { "source_url" => nil, "body" => "First" },
      { "source_url" => nil, "body" => "Second" }
    ])

    assert_no_difference ["FeedEntry.count", "FeedEntryUid.count", "Post.count"] do
      assert_no_enqueued_jobs(only: FeedRefreshJob) do
        assert_raises(Processor::LlmProcessor::InvalidOutput) { FeedRefreshWorkflow.new(feed).execute }
      end
    end

    assert_equal 1, feed.reload.consecutive_failures
    assert_requested request, times: 1
  end

  test "#execute should import every original item and preserve identities through publication" do
    create(:llm_model, model_id: "gpt-4.1")
    feed = ai_feed_with_schedule
    stub_ai_response([
      { "source_url" => nil, "body" => "First story" },
      { "source_url" => nil, "body" => "Second story" }
    ])
    publication = stub_request(:post, "#{feed.access_token.host}/v4/posts")
      .to_return_json(body: { posts: { id: "published-story" } })

    FeedRefreshWorkflow.new(feed).execute

    uids = feed.feed_entries.order(:uid).pluck(:uid)
    assert_equal 2, uids.uniq.size
    assert_equal uids, feed.posts.order(:uid).pluck(:uid)
    assert_equal uids, FeedEntryUid.where(feed: feed).order(:uid).pluck(:uid)

    perform_enqueued_jobs(only: PostPublishJob) { PostPublishJob.perform_now(feed.id) }

    assert_equal 2, feed.posts.where(status: :published).count
    assert_equal uids, feed.posts.order(:uid).pluck(:uid)
    assert_requested publication, times: 2
  end

  test "#execute should deduplicate equivalent source URLs within and across refreshes" do
    create(:llm_model, model_id: "gpt-4.1")
    feed = ai_feed_with_schedule
    stub_ai_response([
      { "source_url" => "http://www.example.com/post/?utm_source=feed", "body" => "First" },
      { "source_url" => "https://example.com/post", "body" => "Duplicate" }
    ])

    FeedRefreshWorkflow.new(feed).execute
    FeedRefreshWorkflow.new(feed).execute

    assert_equal "https://example.com/post", feed.posts.sole.uid
    assert_equal 1, feed.feed_entries.count
  end

  test "#execute should allow independent same-day originals while preserving historical identities" do
    create(:llm_model, model_id: "gpt-4.1")
    feed = ai_feed_with_schedule
    historical = create(:feed_entry, feed: feed, uid: "digest:2026-07-07")
    create(:feed_entry_uid, feed: feed, uid: historical.uid)
    request = stub_ai_response([{ "source_url" => nil, "body" => "A story" }])

    freeze_time do
      FeedRefreshWorkflow.new(feed).execute
      FeedRefreshWorkflow.new(feed).execute
    end

    assert_equal 2, feed.posts.pluck(:uid).uniq.size
    assert_equal "digest:2026-07-07", historical.reload.uid
    assert FeedEntryUid.exists?(feed: feed, uid: historical.uid)
    assert_requested request, times: 2
  end

  test "#execute should accept empty AI output without publication or another refresh" do
    create(:llm_model, model_id: "gpt-4.1")
    feed = ai_feed_with_schedule
    request = stub_ai_response([])
    schedule = feed.feed_schedule.attributes

    assert_no_enqueued_jobs(only: [FeedRefreshJob, PostPublishJob]) do
      assert_empty FeedRefreshWorkflow.new(feed).execute
    end

    assert_empty feed.posts
    assert_equal schedule, feed.feed_schedule.reload.attributes
    assert_requested request, times: 1
  end

  test "#execute should preserve unknown SDK cost in completed refresh statistics" do
    create(:llm_model, model_id: "custom-model")
    credential = create(:ai_credential, :active)
    test_feed = create(:feed, :enabled, user: credential.user, ai_credential: credential,
                                      feed_profile_key: "llm", ai_model: "custom-model",
                                      params: { "prompt" => "Daily roundup" })
    response = JSON.parse(file_fixture("llm_transcripts/completed.json").read)
    response["model"] = "custom-model"
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

    FeedRefreshWorkflow.new(test_feed).execute

    event = Event.find_by!(subject: test_feed, type: "feed_refresh")
    assert_equal "completed", event.metadata["status"]
    assert_equal 1, event.metadata.dig("stats", "llm_calls")
    assert_nil event.metadata.fetch("stats").fetch("llm_cost_cents")
    assert_requested request, times: 1
  end
end
