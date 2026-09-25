require "test_helper"

class FeedRefreshJobThrottlingTest < ActiveJob::TestCase
  test "#perform should defer a throttled refresh without reporting it or counting a failure" do
    freeze_time
    feed = create(:feed, :enabled, consecutive_failures: 9)
    request = stub_request(:get, feed.url).to_return(status: 429, headers: { "Retry-After" => "120" })

    reports = capture_error_reports do
      assert_enqueued_with(job: FeedRefreshJob, args: [feed.id], at: ->(time) { (120.seconds.from_now..125.seconds.from_now).cover?(time) }) do
        FeedRefreshJob.perform_now(feed.id)
      end
    end

    assert_empty reports
    assert_equal 9, feed.reload.consecutive_failures
    assert feed.enabled?
    assert_nil feed.last_successful_refresh_at
    assert_empty feed.posts
    event = feed.events.where(type: "feed_refresh").sole
    assert event.warning?
    assert_equal "throttled", event.metadata["status"]
    assert_equal({ "source_host" => "example.com", "http_status" => 429, "retry_after" => 120 }, event.metadata["rate_limit"])
    assert_requested request, times: 1
  end

  test "#perform should complete successfully when a throttled retry resumes" do
    freeze_time
    feed = create(:feed, :enabled, consecutive_failures: 2)
    request = stub_request(:get, feed.url)
      .to_return(status: 429, headers: { "Retry-After" => "120" })
      .then.to_return(body: '<rss version="2.0"><channel><title>Empty</title></channel></rss>')

    FeedRefreshJob.perform_now(feed.id)
    retry_data = enqueued_jobs.find { |job| job[:job] == FeedRefreshJob }
    clear_enqueued_jobs
    travel_to Time.at(retry_data[:at]) + 1.second

    reports = capture_error_reports do
      assert_no_enqueued_jobs(only: FeedRefreshJob) { ActiveJob::Base.execute(retry_data) }
    end

    assert_empty reports
    assert_equal 0, feed.reload.consecutive_failures
    assert_equal Time.current, feed.last_successful_refresh_at
    assert_equal ["throttled", "completed"], feed.events.where(type: "feed_refresh").order(:created_at).map { |event| event.metadata["status"] }
    assert_requested request, times: 2
  end

  test "#perform should report persistent throttling only when retries are exhausted" do
    feed = create(:feed, :enabled, consecutive_failures: 9)
    stub_request(:get, feed.url).to_return(status: 429)
    job = FeedRefreshJob.new(feed.id)
    job.executions = RateLimited::MAX_ATTEMPTS - 1

    reports = capture_error_reports do
      assert_no_enqueued_jobs(only: FeedRefreshJob) { job.perform_now }
    end

    assert_instance_of Loader::Throttled, reports.sole.error
    assert_equal "example.com", reports.sole.error.source_host
    assert_equal [feed.id], reports.sole.context[:arguments]
    assert_equal 9, feed.reload.consecutive_failures
    assert feed.enabled?
  end

  test "#perform should stop a delayed retry when the feed has been disabled" do
    feed = create(:feed, :disabled)
    job = FeedRefreshJob.new(feed.id)
    job.executions = 1

    assert_no_difference("Event.count") do
      assert_no_enqueued_jobs { job.perform_now }
    end

    assert_not_requested :get, feed.url
  end

  test "#perform should skip an obsolete retry after another refresh succeeded" do
    freeze_time
    feed = create(:feed, :enabled, last_successful_refresh_at: Time.current)
    job = FeedRefreshJob.new(feed.id)
    job.executions = 1
    job.enqueued_at = 1.minute.ago

    assert_no_difference("Event.count") do
      assert_no_enqueued_jobs { job.perform_now }
    end

    assert_not_requested :get, feed.url
  end
end
