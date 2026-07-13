require "test_helper"

class LlmClient::WebSearchAuthErrorTest < ActiveSupport::TestCase
  test "#call records usage and preserves a search auth error" do
    user = create(:user)
    credential = create(:ai_credential, :active, user: user)
    feed = create(
      :feed,
      user: user,
      ai_credential: credential,
      feed_profile_key: "rss",
      params: { "url" => "http://example.com/feed.xml" }
    )
    client = LlmClient.new(credential)
    error = WebSearchProvider::AuthError.new("Serper: HTTP 401")
    client.define_singleton_method(:invoke_provider) { |**| raise error }
    context = LlmClient::CallContext.new(
      feed: feed,
      profile_key: "llm",
      stage: :loader,
      model: "claude-sonnet-4-6"
    )
    usage_count = LlmUsage.count

    raised = assert_raises(WebSearchProvider::AuthError) do
      client.call(context, prompt: "Search", output_schema: nil, web: true)
    end

    assert_equal usage_count + 1, LlmUsage.count
    assert_same error, raised
    assert_equal "provider_error", LlmUsage.last.outcome
    assert_equal "Serper: HTTP 401", LlmUsage.last.error_message
  end
end
