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

  test "#perform should report an ordinary loader failure once with feed context" do
    request = stub_request(:get, feed.url).to_return(status: 404)

    reports = capture_error_reports { FeedRefreshJob.perform_now(feed.id) }

    report = reports.sole
    assert_kind_of Loader::Error, report.error
    assert_equal feed.id, report.context[:feed_id]
    assert report.handled?
    assert_equal "failed", feed.events.find_by!(type: "feed_refresh").metadata["status"]
    assert_equal 1, feed.reload.consecutive_failures
    assert_requested request, times: 1
  end

  test "#perform should retain the cause of a remote connection failure" do
    stub_request(:get, feed.url).to_raise(SocketError.new("Name resolution failed"))

    reports = capture_error_reports { FeedRefreshJob.perform_now(feed.id) }

    error = reports.sole.error
    assert_kind_of Loader::Error, error
    assert_kind_of HttpClient::ConnectionError, error.cause
    assert_equal feed.id, reports.sole.context[:feed_id]
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
