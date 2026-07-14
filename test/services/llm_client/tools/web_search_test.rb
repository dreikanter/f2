require "test_helper"

class LlmClient::Tools::WebSearchTest < ActiveSupport::TestCase
  def credential
    @credential ||= create(:search_credential, :active)
  end

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

  def tool(provider, refresh_event: nil)
    LlmClient::Tools::WebSearch.new(
      provider: provider,
      credential: credential,
      refresh_event: refresh_event
    )
  end

  test "#execute should return normalized results and record one search event" do
    provider = FakeProvider.new(results: [result(1), result(2)])

    assert_difference("Event.where(type: WebSearchUsage::EVENT_TYPE).count", 1) do
      payload = tool(provider).execute(query: "ruby feeds")

      assert_equal [
        { title: "T1", url: "https://1.example", snippet: "s1" },
        { title: "T2", url: "https://2.example", snippet: "s2" }
      ], payload[:results]
    end

    event = Event.where(type: WebSearchUsage::EVENT_TYPE).order(:id).last
    assert_equal credential, event.subject
    assert_equal credential.user, event.user
    assert_equal "debug", event.level
    assert_equal credential.provider, event.metadata.fetch("provider")
    assert_empty event.incoming_event_references
  end

  test "#execute should reference the refresh event when supplied" do
    refresh_event = Event.create!(type: "feed_refresh", level: :info, user: credential.user)

    tool(FakeProvider.new, refresh_event: refresh_event).execute(query: "ruby feeds")

    search_event = Event.where(type: WebSearchUsage::EVENT_TYPE).order(:id).last
    assert_equal search_event, refresh_event.references.sole
  end

  test "#execute should refuse a blank query without hitting the provider or recording usage" do
    provider = FakeProvider.new

    assert_no_difference("Event.where(type: WebSearchUsage::EVENT_TYPE).count") do
      assert_match(/Refused/, tool(provider).execute(query: "  ")[:error])
    end
    assert_empty provider.queries
  end

  test "#execute should surface configuration errors as an error result and record the call" do
    provider = FakeProvider.new(error: WebSearchProvider::ConfigurationError.new("Serper API key missing"))

    assert_difference("Event.where(type: WebSearchUsage::EVENT_TYPE).count", 1) do
      assert_equal "Serper API key missing", tool(provider).execute(query: "ruby feeds")[:error]
    end
  end

  test "#execute should surface provider errors as an error result and record the call" do
    provider = FakeProvider.new(error: WebSearchProvider::ProviderError.new("Serper: HTTP 429"))

    assert_difference("Event.where(type: WebSearchUsage::EVENT_TYPE).count", 1) do
      assert_equal "Serper: HTTP 429", tool(provider).execute(query: "ruby feeds")[:error]
    end
  end

  test "#execute should let auth errors escape after recording the call" do
    provider = FakeProvider.new(error: WebSearchProvider::AuthError.new("Serper: HTTP 401"))

    assert_difference("Event.where(type: WebSearchUsage::EVENT_TYPE).count", 1) do
      assert_raises(WebSearchProvider::AuthError) do
        tool(provider).execute(query: "ruby feeds")
      end
    end
  end

  test "#execute should not fail the search when usage recording breaks" do
    provider = FakeProvider.new(results: [result(1)])
    failing = ->(**) { raise ActiveRecord::RecordInvalid }

    WebSearchUsage.stub(:record!, failing) do
      payload = tool(provider).execute(query: "ruby feeds")

      assert_equal 1, payload[:results].size
    end
  end
end
