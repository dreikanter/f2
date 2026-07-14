require "test_helper"

class LlmClient::Tools::WebSearchTest < ActiveSupport::TestCase
  def result(index)
    WebSearchProvider::Result.new(title: "T#{index}", url: "https://#{index}.example", snippet: "s#{index}")
  end

  # Stands in for a resolved WebSearchProvider: returns canned results or
  # raises, so the tool can be exercised without a real provider.
  class FakeProvider
    attr_reader :queries

    def initialize(results: [], error: nil)
      @results = results
      @error = error
      @queries = []
    end

    def search(query, **)
      @queries << query
      raise @error if @error

      @results
    end
  end

  def tool(provider)
    LlmClient::Tools::WebSearch.new(provider: provider)
  end

  test "#execute should return normalized results as plain hashes" do
    provider = FakeProvider.new(results: [result(1), result(2)])

    payload = tool(provider).execute(query: "ruby feeds")

    assert_equal [
      { title: "T1", url: "https://1.example", snippet: "s1" },
      { title: "T2", url: "https://2.example", snippet: "s2" }
    ], payload[:results]
  end

  test "#execute should refuse a blank query without hitting the provider" do
    provider = FakeProvider.new

    assert_match(/Refused/, tool(provider).execute(query: "  ")[:error])
    assert_empty provider.queries
  end

  test "#execute should surface configuration errors as an error result" do
    provider = FakeProvider.new(error: WebSearchProvider::ConfigurationError.new("Serper API key missing"))

    assert_equal "Serper API key missing", tool(provider).execute(query: "ruby feeds")[:error]
  end

  test "#execute should surface provider errors as an error result" do
    provider = FakeProvider.new(error: WebSearchProvider::ProviderError.new("Serper: HTTP 429"))

    assert_equal "Serper: HTTP 429", tool(provider).execute(query: "ruby feeds")[:error]
  end

  test "#execute should let auth errors escape instead of returning them to the model" do
    provider = FakeProvider.new(error: WebSearchProvider::AuthError.new("Serper: HTTP 401"))

    assert_raises(WebSearchProvider::AuthError) do
      tool(provider).execute(query: "ruby feeds")
    end
  end

  test "#execute should not record events without a credential" do
    provider = FakeProvider.new(results: [result(1)])

    assert_no_difference("Event.count") do
      tool(provider).execute(query: "ruby feeds")
    end
  end

  def credential
    @credential ||= create(:search_credential, :active)
  end

  def feed
    @feed ||= create(:feed, user: credential.user)
  end

  def recording_tool(provider)
    LlmClient::Tools::WebSearch.new(provider: provider, credential: credential, feed: feed, purpose: :scheduled_run)
  end

  test "#execute should record a usage event on the credential for a successful call" do
    provider = FakeProvider.new(results: [result(1)])

    recording_tool(provider).execute(query: "ruby feeds")

    event = Event.find_by!(type: "web_search", subject: credential)
    assert_equal credential.user, event.user
    assert_equal "debug", event.level
    assert_equal "serper", event.metadata["provider"]
    assert_equal "scheduled_run", event.metadata["purpose"]
    assert_equal "success", event.metadata["outcome"]
    assert_equal feed.id, event.metadata["feed_id"]
  end

  test "#execute should record an errored usage event when the provider fails in-band" do
    provider = FakeProvider.new(error: WebSearchProvider::ProviderError.new("Serper: HTTP 429"))

    recording_tool(provider).execute(query: "ruby feeds")

    event = Event.find_by!(type: "web_search", subject: credential)
    assert_equal "error", event.metadata["outcome"]
    assert_equal "Serper: HTTP 429", event.metadata["error"]
  end

  test "#execute should record the call even when an auth error escapes" do
    provider = FakeProvider.new(error: WebSearchProvider::AuthError.new("Serper: HTTP 401"))

    assert_raises(WebSearchProvider::AuthError) do
      recording_tool(provider).execute(query: "ruby feeds")
    end

    event = Event.find_by!(type: "web_search", subject: credential)
    assert_equal "error", event.metadata["outcome"]
    assert_equal "Serper: HTTP 401", event.metadata["error"]
  end

  test "#execute should not record an event for a refused blank query" do
    provider = FakeProvider.new

    assert_no_difference("Event.count") do
      recording_tool(provider).execute(query: "  ")
    end
  end

  test "#execute should not fail the search when event recording breaks" do
    provider = FakeProvider.new(results: [result(1)])
    failing = recording_tool(provider)
    credential.stub(:record_search_call, ->(**) { raise ActiveRecord::RecordInvalid }) do
      payload = failing.execute(query: "ruby feeds")

      assert_equal 1, payload[:results].size
    end
  end
end
