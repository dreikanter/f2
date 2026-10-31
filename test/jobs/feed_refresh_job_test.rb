require "test_helper"

class FeedRefreshJobTest < ActiveJob::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "rss")
  end

  test "#perform should ignore a missing feed" do
    assert_nothing_raised do
      FeedRefreshJob.perform_now(-1)
    end
  end

  test "#perform should no-op for a webhook feed instead of resolving its missing loader" do
    webhook_feed = create(:feed, :webhook, state: :enabled)

    assert_no_difference("Event.count") do
      assert_nothing_raised do
        FeedRefreshJob.perform_now(webhook_feed.id)
      end
    end
  end

  test "#perform should count loader failures" do
    WebMock.stub_request(:get, feed.url).to_return(status: 500)

    incremented = false
    Metrics.stub(:increment, ->(*args, **) { incremented = true if args.first == "loader_errors_total" }) do
      FeedRefreshJob.perform_now(feed.id)
    end

    assert incremented
  end

  test "#perform should record a missing source without reporting a bug" do
    request = stub_request(:get, feed.url).to_return(status: 404)

    reports = capture_error_reports { FeedRefreshJob.perform_now(feed.id) }

    assert_empty reports
    event = feed.events.find_by!(type: "feed_refresh")
    assert_equal "failed", event.metadata["status"]
    assert_equal "HTTP 404", event.message
    assert_equal 1, feed.reload.consecutive_failures
    assert_requested request, times: 1
  end

  test "#perform should record source throttling without reporting a bug or retrying immediately" do
    request = stub_request(:get, feed.url).to_return(status: 429)

    reports = capture_error_reports do
      assert_no_enqueued_jobs(only: FeedRefreshJob) { FeedRefreshJob.perform_now(feed.id) }
    end

    assert_empty reports
    event = feed.events.find_by!(type: "feed_refresh")
    assert_equal "failed", event.metadata["status"]
    assert_equal "HTTP 429", event.message
    assert_requested request, times: 1
  end

  test "#perform should record a missing YouTube feed without reporting a bug" do
    url = "https://www.youtube.com/feeds/videos.xml?channel_id=UC123"
    feed = create(:feed, feed_profile_key: "youtube", params: { "url" => url })
    request = stub_request(:get, url).to_return(status: 404)

    reports = capture_error_reports { FeedRefreshJob.perform_now(feed.id) }

    assert_empty reports
    assert_equal "HTTP 404", feed.events.find_by!(type: "feed_refresh").message
    assert_equal 1, feed.reload.consecutive_failures
    assert_requested request, times: 1
  end

  test "#perform should still report other loader failures once with feed context" do
    request = stub_request(:get, feed.url).to_return(status: 302, headers: { "Location" => feed.url })

    reports = capture_error_reports { FeedRefreshJob.perform_now(feed.id) }

    report = reports.sole
    assert_kind_of Loader::Error, report.error
    assert_equal feed.id, report.context[:feed_id]
    assert_equal feed.user_id, report.context[:feed_owner_id]
    assert_equal feed.user.name, report.context[:feed_owner_label]
    assert_equal "candy.freefeed.net", report.context[:freefeed_instance]
    assert_equal feed.target_group, report.context[:target_group]
    assert report.handled?
    assert_equal "failed", feed.events.find_by!(type: "feed_refresh").metadata["status"]
    assert_equal 1, feed.reload.consecutive_failures
    assert_requested request, times: 4
  end

  test "#perform should enrich errors reported inside the workflow" do
    workflow = FeedRefreshWorkflow.new(feed)
    error = RuntimeError.new("Entry normalization failed")

    reports = capture_error_reports do
      FeedRefreshWorkflow.stub(:new, workflow) do
        workflow.stub(:execute, -> { Rails.error.report(error, context: { entry_uid: "entry-123" }) }) do
          FeedRefreshJob.perform_now(feed.id)
        end
      end
    end

    context = reports.sole.context
    assert_equal feed.id, context[:feed_id]
    assert_equal feed.user_id, context[:feed_owner_id]
    assert_equal "entry-123", context[:entry_uid]
  end

  test "#perform should retain context for an unhandled error reported outside the job" do
    workflow = FeedRefreshWorkflow.new(feed)
    error = RuntimeError.new("Unexpected workflow failure")

    reports = capture_error_reports do
      FeedRefreshWorkflow.stub(:new, workflow) do
        workflow.stub(:execute, -> { raise error }) do
          assert_raises(RuntimeError) do
            Rails.error.record { FeedRefreshJob.perform_now(feed.id) }
          end
        end
      end
    end

    report = reports.sole
    assert_same error, report.error
    assert_not report.handled?
    assert_equal feed.id, report.context[:feed_id]
    assert_equal feed.user_id, report.context[:feed_owner_id]
  end

  test "#perform should isolate feed context between job executions" do
    other_feed = create(:feed, :without_access_token)
    stub_request(:get, feed.url).to_return(status: 302, headers: { "Location" => feed.url })

    reports = capture_error_reports do
      [feed, other_feed].each do |current_feed|
        Rails.application.executor.wrap { FeedRefreshJob.perform_now(current_feed.id) }
      end

      Rails.error.report(RuntimeError.new("Unrelated failure"))
    end

    first, second, unrelated = reports
    assert_equal 3, reports.size
    assert_equal "candy.freefeed.net", first.context[:freefeed_instance]
    assert_equal other_feed.id, second.context[:feed_id]
    assert_equal other_feed.user_id, second.context[:feed_owner_id]
    assert_nil second.context[:freefeed_instance]
    assert_nil second.context[:target_group]
    assert_empty unrelated.context.slice(*FeedErrorContext.for(feed).keys)
  end

  test "#perform should record invalid source content without reporting a bug or retrying" do
    post = create(:post, :published, feed: feed)
    request = stub_request(:get, feed.url)
      .to_return(status: 200, body: "<html><body>Temporarily unavailable</body></html>")

    reports = capture_error_reports do
      assert_no_difference ["Post.count", "FeedEntry.count"] do
        assert_no_enqueued_jobs(only: FeedRefreshJob) { FeedRefreshJob.perform_now(feed.id) }
      end
    end

    assert_empty reports
    event = feed.events.find_by!(type: "feed_refresh")
    assert_equal "failed", event.metadata["status"]
    assert_equal "process_feed_contents", event.metadata.dig("error", "stage")
    assert_equal "Feedjira::NoParserAvailable", event.metadata.dig("error", "class")
    assert_equal 1, feed.reload.consecutive_failures
    assert_predicate post.reload, :published?
    assert_requested request, times: 1
  end

  test "#perform should still complete a valid empty RSS feed" do
    stub_request(:get, feed.url)
      .to_return(body: '<rss version="2.0"><channel><title>Empty feed</title></channel></rss>')

    FeedRefreshJob.perform_now(feed.id)

    assert_equal "completed", feed.events.find_by!(type: "feed_refresh").metadata["status"]
    assert_equal 0, feed.reload.consecutive_failures
    assert_empty feed.posts
  end

  test "#perform should record a connection failure without reporting a bug or retrying" do
    request = stub_request(:get, feed.url).to_raise(SocketError.new("Name resolution failed"))

    reports = capture_error_reports do
      assert_no_enqueued_jobs(only: FeedRefreshJob) { FeedRefreshJob.perform_now(feed.id) }
    end

    assert_empty reports
    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "failed", event.metadata["status"]
    assert_match(/Name resolution failed/, event.message)
    assert_equal 1, feed.reload.consecutive_failures
    assert_requested request, times: 1
  end

  test "#perform should count a read timeout without reporting a bug or retrying" do
    request = stub_request(:get, feed.url).to_raise(Net::ReadTimeout.new("read timed out"))
    increments = []

    reports = capture_error_reports do
      Metrics.stub(:increment, ->(name, **labels) { increments << [name, labels] }) do
        assert_no_enqueued_jobs(only: FeedRefreshJob) { FeedRefreshJob.perform_now(feed.id) }
      end
    end

    assert_empty reports
    assert_includes increments, ["loader_errors_total", { profile: "rss", loader: "HttpLoader" }]
    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "failed", event.metadata["status"]
    assert_equal "load_feed_contents", event.metadata.dig("error", "stage")
    assert_match(/read timed out/, event.message)
    assert_equal 1, feed.reload.consecutive_failures
    assert_requested request, times: 1
  end

  test "#perform should still disable a feed after repeated transport failures" do
    feed = create(:feed, :enabled, feed_profile_key: "rss", consecutive_failures: Feed::MAX_CONSECUTIVE_FAILURES - 1)
    stub_request(:get, feed.url).to_timeout

    reports = capture_error_reports { FeedRefreshJob.perform_now(feed.id) }

    assert_empty reports
    assert_predicate feed.reload, :disabled?
    assert_equal "failed", feed.events.find_by!(type: "feed_refresh").metadata["status"]
  end

  test ".perform_now should skip without raising when the feed is already being refreshed" do
    feed = create(:feed, feed_profile_key: "rss")

    # with_advisory_lock! raises on contention; the job rescues it and skips.
    Feed.stub(:with_advisory_lock!, ->(*, **) { raise WithAdvisoryLock::FailedToAcquireLock.new("feed_refresh") }) do
      assert_nothing_raised do
        FeedRefreshJob.perform_now(feed.id)
      end
    end
  end

  test "#perform should allow a manual refresh to import another original post" do
    response = JSON.parse(file_fixture("llm_transcripts/completed.json").read)
    response["output"].last["content"].first["text"] = '{"items":[{"source_url":null,"body":"A story"}]}'
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

    FeedRefreshJob.perform_now(ai_feed.id)
    FeedRefreshJob.perform_now(ai_feed.id)

    assert_equal 2, ai_feed.posts.pluck(:uid).uniq.size
    assert_requested request, times: 2
  end

  test "#perform should record an AI failure without queuing a retry" do
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return(status: 400, body: "Bad request")

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedRefreshJob.perform_now(ai_feed.id)
    end

    assert_equal 1, ai_feed.reload.consecutive_failures
    assert_empty ai_feed.posts
    assert_requested request, times: 1
  end

  private

  def ai_feed
    @ai_feed ||= begin
      create(:llm_model, model_id: "gpt-5-nano")
      credential = create(:ai_credential, :active)
      create(:feed, :enabled, user: credential.user, feed_profile_key: "llm",
                            params: { "prompt" => "Daily roundup" }, ai_credential: credential,
                            ai_model: "gpt-5-nano", search_credential: nil)
    end
  end
end
