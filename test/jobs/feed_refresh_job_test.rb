require "test_helper"

class FeedRefreshJobTest < ActiveJob::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "rss")
  end

  test "handles missing feed gracefully" do
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

  test "does not raise when the loader raises Loader::Error" do
    WebMock.stub_request(:get, feed.url).to_return(status: 500)

    assert_nothing_raised do
      FeedRefreshJob.perform_now(feed.id)
    end
  end

  test "increments loader_errors_total metric when the loader raises Loader::Error" do
    WebMock.stub_request(:get, feed.url).to_return(status: 500)

    incremented = false
    Metrics.stub(:increment, ->(*args, **) { incremented = true if args.first == "loader_errors_total" }) do
      FeedRefreshJob.perform_now(feed.id)
    end

    assert incremented
  end

  test "does not report Loader::Error to the error tracker" do
    WebMock.stub_request(:get, feed.url).to_return(status: 404)

    reported = false
    Rails.error.stub(:report, ->(*, **) { reported = true }) do
      FeedRefreshJob.perform_now(feed.id)
    end

    assert_not reported
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

  test ".perform_now should forward manual: true to the workflow" do
    assert_equal true, captured_manual_flag { FeedRefreshJob.perform_now(feed.id, manual: true) }
  end

  test ".perform_now should default the workflow to a scheduled (non-manual) run" do
    assert_equal false, captured_manual_flag { FeedRefreshJob.perform_now(feed.id) }
  end

  private

  # Stubs the workflow so it doesn't run, capturing the manual: flag the job
  # hands it. A digest feed's cadence skip hinges on this flag being scheduled
  # by default and forced through only on a user-initiated refresh.
  def captured_manual_flag
    captured = nil
    fake_workflow = Object.new
    fake_workflow.define_singleton_method(:execute) { nil }

    FeedRefreshWorkflow.stub(:new, ->(_feed, **kwargs) { captured = kwargs[:manual]; fake_workflow }) do
      yield
    end

    captured
  end
end
