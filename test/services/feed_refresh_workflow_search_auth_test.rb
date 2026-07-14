require "test_helper"

class FeedRefreshWorkflowSearchAuthTest < ActiveSupport::TestCase
  test "search auth failure deactivates the credential, disables its feeds, and records a failed run" do
    user = create(:user)
    ai_credential = create(
      :ai_credential,
      :active,
      user: user,
      available_models: [{ "id" => "claude-sonnet-4-6" }]
    )
    search_credential = create(:search_credential, :active, user: user)
    feed = create(
      :feed,
      :enabled,
      user: user,
      feed_profile_key: "llm",
      params: { "prompt" => "daily roundup" },
      ai_credential: ai_credential,
      ai_model: "claude-sonnet-4-6",
      search_credential: search_credential
    )
    dependent_feed = create(
      :feed,
      :enabled,
      user: user,
      feed_profile_key: "llm",
      params: { "prompt" => "weekly roundup" },
      ai_credential: ai_credential,
      ai_model: "claude-sonnet-4-6",
      search_credential: search_credential
    )
    error = WebSearchProvider::AuthError.new("Serper: HTTP 401")
    loader = Object.new
    loader.define_singleton_method(:load) { raise error }

    raised = assert_raises(WebSearchProvider::AuthError) do
      feed.stub(:loader_instance, loader) { FeedRefreshWorkflow.new(feed).execute }
    end

    assert_same error, raised
    assert search_credential.reload.inactive?
    assert_equal error.message, search_credential.last_error
    assert feed.reload.disabled?
    assert dependent_feed.reload.disabled?

    deactivation = Event.find_by!(subject: search_credential, type: "search_credential_deactivated")
    assert deactivation.warning?

    refresh = Event.where(subject: feed, type: "feed_refresh").order(:created_at).last
    assert_equal "failed", refresh.metadata["status"]
    assert_equal "WebSearchProvider::AuthError", refresh.metadata.dig("error", "class")
    assert_equal error.message, refresh.message
  end
end
