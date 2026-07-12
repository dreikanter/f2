require "test_helper"

class WebSearchTest < ActiveSupport::TestCase
  ALL_ENV_KEYS = %w[WEB_SEARCH_PROVIDER SERPER_API_KEY BRAVE_SEARCH_API_KEY TAVILY_API_KEY].freeze

  def with_env(vars)
    vars = ALL_ENV_KEYS.index_with { nil }.merge(vars)
    saved = vars.keys.index_with { |key| ENV[key] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  def stub_response(body)
    response = HttpClient::Response.new(status: 200, body: body)
    client = Object.new
    client.define_singleton_method(:post) { |*, **| response }
    client.define_singleton_method(:get) { |*, **| response }
    client
  end

  test ".search should route to the named provider" do
    body = { results: [{ title: "T", url: "https://t.example", content: "s" }] }.to_json

    with_env("TAVILY_API_KEY" => "key") do
      HttpClient.stub(:build, ->(**) { stub_response(body) }) do
        results = WebSearch.search("query", provider: :tavily)
        assert_equal [WebSearch::Result.new(title: "T", url: "https://t.example", snippet: "s")], results
      end
    end
  end

  test ".search should use the default provider when none is named" do
    body = { organic: [{ title: "T", link: "https://t.example", snippet: "s" }] }.to_json

    with_env("WEB_SEARCH_PROVIDER" => "serper", "SERPER_API_KEY" => "key") do
      HttpClient.stub(:build, ->(**) { stub_response(body) }) do
        assert_equal ["https://t.example"], WebSearch.search("query").map(&:url)
      end
    end
  end

  test ".search should raise ArgumentError for a blank query" do
    assert_raises(ArgumentError) { WebSearch.search("  ") }
    assert_raises(ArgumentError) { WebSearch.search(nil) }
  end

  test ".search should raise ConfigurationError for an unknown provider" do
    assert_raises(WebSearch::ConfigurationError) { WebSearch.search("query", provider: "nope") }
  end

  test ".configured? should be false when no provider has a key" do
    with_env({}) do
      assert_not WebSearch.configured?
    end
  end

  test ".configured? should be true when a provider has a key" do
    with_env("BRAVE_SEARCH_API_KEY" => "key") do
      assert WebSearch.configured?
    end
  end

  test ".configured? should be false when WEB_SEARCH_PROVIDER names a provider without a key" do
    with_env("WEB_SEARCH_PROVIDER" => "serper", "TAVILY_API_KEY" => "key") do
      assert_not WebSearch.configured?
    end
  end
end
