require "test_helper"

class WebSearch::ProviderTest < ActiveSupport::TestCase
  ALL_ENV_KEYS = %w[WEB_SEARCH_PROVIDER SERPER_API_KEY BRAVE_SEARCH_API_KEY TAVILY_API_KEY].freeze

  # Records every request a provider makes, so request shapes can be asserted
  # without touching the network.
  class RecordingClient
    attr_reader :calls

    def initialize(response)
      @response = response
      @calls = []
    end

    def get(url, headers: {}, options: {})
      @calls << { method: :get, url: url, headers: headers }
      @response
    end

    def post(url, body: nil, headers: {}, options: {})
      @calls << { method: :post, url: url, body: body, headers: headers }
      @response
    end
  end

  def ok_response(body)
    HttpClient::Response.new(status: 200, body: body)
  end

  def with_client(response)
    client = RecordingClient.new(response)
    HttpClient.stub(:build, ->(**) { client }) { yield client }
  end

  def with_env(vars)
    vars = ALL_ENV_KEYS.index_with { nil }.merge(vars)
    saved = vars.keys.index_with { |key| ENV[key] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  test ".for should return the named provider" do
    assert_instance_of WebSearch::Provider::Serper, WebSearch::Provider.for("serper")
    assert_instance_of WebSearch::Provider::Brave, WebSearch::Provider.for("brave")
    assert_instance_of WebSearch::Provider::Tavily, WebSearch::Provider.for("tavily")
  end

  test ".for should accept a symbol provider" do
    assert_instance_of WebSearch::Provider::Serper, WebSearch::Provider.for(:serper)
  end

  test ".for should raise for an unknown provider" do
    error = assert_raises(WebSearch::ConfigurationError) { WebSearch::Provider.for("nope") }
    assert_match(/unknown web search provider/, error.message)
  end

  test "every registered provider should inherit from Base" do
    WebSearch::Provider::REGISTRY.each_key do |name|
      assert_kind_of WebSearch::Provider::Base, WebSearch::Provider.for(name)
    end
  end

  test ".default should respect WEB_SEARCH_PROVIDER" do
    with_env("WEB_SEARCH_PROVIDER" => "tavily") do
      assert_instance_of WebSearch::Provider::Tavily, WebSearch::Provider.default
    end
  end

  test ".default should fall back to the first provider with an API key" do
    with_env("TAVILY_API_KEY" => "key") do
      assert_instance_of WebSearch::Provider::Tavily, WebSearch::Provider.default
    end
  end

  test ".default should raise when nothing is configured" do
    with_env({}) do
      assert_raises(WebSearch::ConfigurationError) { WebSearch::Provider.default }
    end
  end

  test "every provider #search should raise ConfigurationError when its key is missing" do
    with_env({}) do
      with_client(ok_response("{}")) do |client|
        WebSearch::Provider::REGISTRY.each_key do |name|
          assert_raises(WebSearch::ConfigurationError, name) do
            WebSearch::Provider.for(name).search("query")
          end
        end
        assert_empty client.calls
      end
    end
  end

  test "serper #search should post the query with the API key header" do
    body = { organic: [{ title: "A", link: "https://a.example", snippet: "sa" }] }.to_json

    with_env("SERPER_API_KEY" => "serper-key") do
      with_client(ok_response(body)) do |client|
        results = WebSearch::Provider::Serper.new.search("ruby feeds", max_results: 3)

        call = client.calls.sole
        assert_equal :post, call[:method]
        assert_equal "https://google.serper.dev/search", call[:url]
        assert_equal "serper-key", call[:headers]["X-API-KEY"]
        assert_equal({ "q" => "ruby feeds", "num" => 3 }, JSON.parse(call[:body]))
        assert_equal [WebSearch::Result.new(title: "A", url: "https://a.example", snippet: "sa")], results
      end
    end
  end

  test "brave #search should get the query with the subscription token header" do
    body = { web: { results: [{ title: "B", url: "https://b.example", description: "sb" }] } }.to_json

    with_env("BRAVE_SEARCH_API_KEY" => "brave-key") do
      with_client(ok_response(body)) do |client|
        results = WebSearch::Provider::Brave.new.search("ruby feeds", max_results: 3)

        call = client.calls.sole
        assert_equal :get, call[:method]
        assert_equal "https://api.search.brave.com/res/v1/web/search?q=ruby+feeds&count=3", call[:url]
        assert_equal "brave-key", call[:headers]["X-Subscription-Token"]
        assert_equal [WebSearch::Result.new(title: "B", url: "https://b.example", snippet: "sb")], results
      end
    end
  end

  test "tavily #search should post the query with a bearer token" do
    body = { results: [{ title: "C", url: "https://c.example", content: "sc" }] }.to_json

    with_env("TAVILY_API_KEY" => "tavily-key") do
      with_client(ok_response(body)) do |client|
        results = WebSearch::Provider::Tavily.new.search("ruby feeds", max_results: 3)

        call = client.calls.sole
        assert_equal :post, call[:method]
        assert_equal "https://api.tavily.com/search", call[:url]
        assert_equal "Bearer tavily-key", call[:headers]["Authorization"]
        assert_equal({ "query" => "ruby feeds", "max_results" => 3 }, JSON.parse(call[:body]))
        assert_equal [WebSearch::Result.new(title: "C", url: "https://c.example", snippet: "sc")], results
      end
    end
  end

  test "#search should cap results at max_results even when the provider returns more" do
    organic = (1..5).map { |i| { title: "T#{i}", link: "https://#{i}.example", snippet: "s#{i}" } }

    with_env("SERPER_API_KEY" => "key") do
      with_client(ok_response({ organic: organic }.to_json)) do
        results = WebSearch::Provider::Serper.new.search("query", max_results: 2)
        assert_equal %w[T1 T2], results.map(&:title)
      end
    end
  end

  test "#search should clamp max_results into the supported range" do
    with_env("SERPER_API_KEY" => "key") do
      with_client(ok_response({ organic: [] }.to_json)) do |client|
        WebSearch::Provider::Serper.new.search("query", max_results: 99)
        assert_equal 10, JSON.parse(client.calls.sole[:body]).fetch("num")
      end
    end
  end

  test "#search should raise ProviderError on a non-success HTTP status" do
    with_env("SERPER_API_KEY" => "key") do
      with_client(HttpClient::Response.new(status: 429, body: "")) do
        error = assert_raises(WebSearch::ProviderError) { WebSearch::Provider::Serper.new.search("query") }
        assert_equal "Serper: HTTP 429", error.message
      end
    end
  end

  test "#search should raise ProviderError on an unparseable response" do
    with_env("SERPER_API_KEY" => "key") do
      with_client(ok_response("<html>oops</html>")) do
        error = assert_raises(WebSearch::ProviderError) { WebSearch::Provider::Serper.new.search("query") }
        assert_match(/unparseable response/, error.message)
      end
    end
  end

  test "#search should raise ProviderError on a transport error" do
    raising = Object.new
    def raising.post(_url, **) = raise(HttpClient::TimeoutError, "timed out")

    with_env("SERPER_API_KEY" => "key") do
      HttpClient.stub(:build, ->(**) { raising }) do
        error = assert_raises(WebSearch::ProviderError) { WebSearch::Provider::Serper.new.search("query") }
        assert_equal "Serper: timed out", error.message
      end
    end
  end

  test "#search should tolerate a payload without results" do
    with_env("SERPER_API_KEY" => "key") do
      with_client(ok_response("{}")) do
        assert_empty WebSearch::Provider::Serper.new.search("query")
      end
    end
  end
end
