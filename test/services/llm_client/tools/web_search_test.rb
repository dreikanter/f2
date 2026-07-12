require "test_helper"

class LlmClient::Tools::WebSearchTest < ActiveSupport::TestCase
  def tool = LlmClient::Tools::WebSearch.new

  def result(index)
    WebSearch::Result.new(title: "T#{index}", url: "https://#{index}.example", snippet: "s#{index}")
  end

  test "#execute should return normalized results as plain hashes" do
    WebSearch.stub(:configured?, true) do
      WebSearch.stub(:search, [result(1), result(2)]) do
        payload = tool.execute(query: "ruby feeds")

        assert_equal [
          { title: "T1", url: "https://1.example", snippet: "s1" },
          { title: "T2", url: "https://2.example", snippet: "s2" }
        ], payload[:results]
      end
    end
  end

  test "#execute should refuse a blank query without searching" do
    WebSearch.stub(:search, ->(*) { flunk "search should not be called" }) do
      assert_match(/Refused/, tool.execute(query: "  ")[:error])
    end
  end

  test "#execute should report when no provider is configured" do
    WebSearch.stub(:configured?, false) do
      assert_equal "Web search is not configured.", tool.execute(query: "ruby feeds")[:error]
    end
  end

  test "#execute should surface provider errors as an error result" do
    WebSearch.stub(:configured?, true) do
      WebSearch.stub(:search, ->(*, **) { raise WebSearch::ProviderError, "Serper: HTTP 429" }) do
        assert_equal "Serper: HTTP 429", tool.execute(query: "ruby feeds")[:error]
      end
    end
  end
end
