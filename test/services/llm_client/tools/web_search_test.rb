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

  test "#execute should surface auth errors as an error result" do
    provider = FakeProvider.new(error: WebSearchProvider::AuthError.new("Serper: HTTP 401"))

    assert_equal "Serper: HTTP 401", tool(provider).execute(query: "ruby feeds")[:error]
  end
end
