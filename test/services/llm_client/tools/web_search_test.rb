require "test_helper"

class LlmClient::Tools::WebSearchTest < ActiveSupport::TestCase
  def tool = LlmClient::Tools::WebSearch.new

  def result(index)
    WebSearchProvider::Result.new(title: "T#{index}", url: "https://#{index}.example", snippet: "s#{index}")
  end

  # Stands in for a resolved WebSearchProvider: returns canned results or
  # raises, so the tool can be exercised without a real provider.
  class FakeProvider
    def initialize(results: [], error: nil)
      @results = results
      @error = error
    end

    def search(_query, **)
      raise @error if @error

      @results
    end
  end

  test "#execute should return normalized results as plain hashes" do
    provider = FakeProvider.new(results: [result(1), result(2)])

    WebSearchProvider.stub(:default, provider) do
      payload = tool.execute(query: "ruby feeds")

      assert_equal [
        { title: "T1", url: "https://1.example", snippet: "s1" },
        { title: "T2", url: "https://2.example", snippet: "s2" }
      ], payload[:results]
    end
  end

  test "#execute should refuse a blank query without resolving a provider" do
    WebSearchProvider.stub(:default, ->(*) { flunk "default should not be resolved" }) do
      assert_match(/Refused/, tool.execute(query: "  ")[:error])
    end
  end

  test "#execute should report when no provider is configured" do
    unconfigured = -> { raise WebSearchProvider::ConfigurationError, "no web search provider configured" }

    WebSearchProvider.stub(:default, unconfigured) do
      assert_equal "no web search provider configured", tool.execute(query: "ruby feeds")[:error]
    end
  end

  test "#execute should surface provider errors as an error result" do
    provider = FakeProvider.new(error: WebSearchProvider::ProviderError.new("Serper: HTTP 429"))

    WebSearchProvider.stub(:default, provider) do
      assert_equal "Serper: HTTP 429", tool.execute(query: "ruby feeds")[:error]
    end
  end
end
