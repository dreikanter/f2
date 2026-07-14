require "test_helper"

class FeedRefreshWorkflowSearchCallsTest < ActiveSupport::TestCase
  def empty_rss
    <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"><channel><title>Empty</title></channel></rss>
    RSS
  end

  def refresh_feed
    @refresh_feed ||= create(:feed, :enabled, feed_profile_key: "rss")
  end

  def credential
    @credential ||= create(:search_credential, :active, user: refresh_feed.user)
  end

  # Stands in for a run whose gather step performed web searches: records the
  # per-call events mid-load, the way the WebSearch tool does.
  def search_recording_loader(rss, purpose: :scheduled_run, error: nil)
    recorded_credential = credential
    recorded_feed = refresh_feed
    loader = Object.new
    loader.define_singleton_method(:load) do
      recorded_credential.record_search_call(purpose: purpose, outcome: :success, feed: recorded_feed)
      raise error if error

      rss
    end
    loader
  end

  test "#execute should count and reference the run's search calls on the completed event" do
    prior_call = credential.record_search_call(purpose: :scheduled_run, outcome: :success, feed: refresh_feed)

    refresh_feed.stub(:loader_instance, search_recording_loader(empty_rss)) do
      FeedRefreshWorkflow.new(refresh_feed).execute
    end

    event = Event.find_by!(subject: refresh_feed, type: "feed_refresh")
    run_call = Event.where(type: "web_search").where.not(id: prior_call.id).sole

    assert_equal "completed", event.metadata["status"]
    assert_equal 1, event.metadata.dig("stats", "search_calls")
    assert_includes event.references, run_call
    assert_not_includes event.references, prior_call
  end

  test "#execute should count and reference the run's search calls on the failed event" do
    error = LlmClient::ProviderError.new("server error")

    refresh_feed.stub(:loader_instance, search_recording_loader(empty_rss, error: error)) do
      assert_raises(LlmClient::ProviderError) { FeedRefreshWorkflow.new(refresh_feed).execute }
    end

    event = Event.find_by!(subject: refresh_feed, type: "feed_refresh")

    assert_equal "failed", event.metadata["status"]
    assert_equal 1, event.metadata.dig("stats", "search_calls")
    assert_includes event.references, Event.where(type: "web_search").sole
  end

  test "#execute should record no search stats for a run without searches" do
    refresh_feed.stub(:loader_instance, Object.new.tap { |l| rss = empty_rss; l.define_singleton_method(:load) { rss } }) do
      FeedRefreshWorkflow.new(refresh_feed).execute
    end

    event = Event.find_by!(subject: refresh_feed, type: "feed_refresh")

    assert_not event.metadata["stats"].key?("search_calls")
  end

  test "#execute should not count another purpose's calls in the run window" do
    refresh_feed.stub(:loader_instance, search_recording_loader(empty_rss, purpose: :preview)) do
      FeedRefreshWorkflow.new(refresh_feed).execute
    end

    event = Event.find_by!(subject: refresh_feed, type: "feed_refresh")

    assert_not event.metadata["stats"].key?("search_calls")
  end
end
