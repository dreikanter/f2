require "test_helper"

class FeedRefreshWorkflowSearchCallsTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:search_credential, :active, user: user)
  end

  def refresh_feed
    @refresh_feed ||= begin
      ai_credential = create(:ai_credential, :active, user: user,
                                                      available_models: [{ "id" => "claude-sonnet-4-6" }])
      create(:feed, :enabled, user: user,
                              feed_profile_key: "llm",
                              params: { "prompt" => "daily roundup" },
                              ai_credential: ai_credential,
                              ai_model: "claude-sonnet-4-6",
                              search_credential: credential)
    end
  end

  def plain_loader(items)
    loader = Object.new
    loader.define_singleton_method(:load) { items }
    loader
  end

  # Stands in for a run whose gather step performed web searches: records the
  # per-call events mid-load, the way the WebSearch tool does.
  def search_recording_loader(purpose: :scheduled_run, error: nil)
    recorded_credential = credential
    recorded_feed = refresh_feed
    loader = Object.new
    loader.define_singleton_method(:load) do
      recorded_credential.record_search_call(purpose: purpose, outcome: :success, feed: recorded_feed)
      raise error if error

      []
    end
    loader
  end

  test "#execute should count and reference the run's search calls on the completed event" do
    prior_call = credential.record_search_call(purpose: :scheduled_run, outcome: :success, feed: refresh_feed)

    refresh_feed.stub(:loader_instance, search_recording_loader) do
      FeedRefreshWorkflow.new(refresh_feed).execute
    end

    event = Event.find_by!(subject: refresh_feed, type: "feed_refresh")
    run_call = Event.web_search.where.not(id: prior_call.id).sole

    assert_equal "completed", event.metadata["status"]
    assert_equal 1, event.metadata.dig("stats", "search_calls")
    assert_includes event.references, run_call
    assert_not_includes event.references, prior_call
  end

  test "#execute should count and reference the run's search calls on the failed event" do
    error = LlmClient::ProviderError.new("server error")

    refresh_feed.stub(:loader_instance, search_recording_loader(error: error)) do
      assert_raises(LlmClient::ProviderError) { FeedRefreshWorkflow.new(refresh_feed).execute }
    end

    event = Event.find_by!(subject: refresh_feed, type: "feed_refresh")

    assert_equal "failed", event.metadata["status"]
    assert_equal 1, event.metadata.dig("stats", "search_calls")
    assert_includes event.references, Event.web_search.sole
  end

  test "#execute should record no search stats for a run without searches" do
    refresh_feed.stub(:loader_instance, plain_loader([])) do
      FeedRefreshWorkflow.new(refresh_feed).execute
    end

    event = Event.find_by!(subject: refresh_feed, type: "feed_refresh")

    assert_not event.metadata["stats"].key?("search_calls")
  end

  test "#execute should not count another purpose's calls in the run window" do
    refresh_feed.stub(:loader_instance, search_recording_loader(purpose: :preview)) do
      FeedRefreshWorkflow.new(refresh_feed).execute
    end

    event = Event.find_by!(subject: refresh_feed, type: "feed_refresh")

    assert_not event.metadata["stats"].key?("search_calls")
  end

  test "#execute should skip the search event query for deterministic feeds" do
    rss_feed = create(:feed, :enabled, feed_profile_key: "rss")
    rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"><channel><title>Empty</title></channel></rss>
    RSS

    assert_no_queries_match(/web_search/) do
      rss_feed.stub(:loader_instance, plain_loader(rss)) do
        FeedRefreshWorkflow.new(rss_feed).execute
      end
    end

    event = Event.find_by!(subject: rss_feed, type: "feed_refresh")
    assert_equal "completed", event.metadata["status"]
  end
end
