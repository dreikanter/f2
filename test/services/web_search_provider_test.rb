require "test_helper"

class WebSearchProviderTest < ActiveSupport::TestCase
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

  test ".for should build the named provider around the given key" do
    provider = WebSearchProvider.for("serper", api_key: "key")
    assert_instance_of WebSearchProvider::Serper, provider
    assert provider.configured?
  end

  test ".for should accept a symbol provider" do
    assert_instance_of WebSearchProvider::Brave, WebSearchProvider.for(:brave, api_key: "key")
  end

  test ".for should raise for an unknown provider" do
    error = assert_raises(WebSearchProvider::ConfigurationError) { WebSearchProvider.for("nope", api_key: "key") }
    assert_match(/unknown web search provider/, error.message)
  end

  test "every registered provider should inherit from Base" do
    WebSearchProvider::REGISTRY.each_key do |name|
      assert_kind_of WebSearchProvider::Base, WebSearchProvider.for(name, api_key: "key")
    end
  end

  test "serper #search should post the query with the API key header" do
    body = { organic: [{ title: "A", link: "https://a.example", snippet: "sa" }] }.to_json

    with_client(ok_response(body)) do |client|
      results = WebSearchProvider::Serper.new(api_key: "serper-key").search("ruby feeds", max_results: 3)

      call = client.calls.sole
      assert_equal :post, call[:method]
      assert_equal "https://google.serper.dev/search", call[:url]
      assert_equal "serper-key", call[:headers]["X-API-KEY"]
      assert_equal({ "q" => "ruby feeds", "num" => 3 }, JSON.parse(call[:body]))
      assert_equal [WebSearchProvider::Result.new(title: "A", url: "https://a.example", snippet: "sa")], results
    end
  end

  test "brave #search should get the query with the subscription token header" do
    body = { web: { results: [{ title: "B", url: "https://b.example", description: "sb" }] } }.to_json

    with_client(ok_response(body)) do |client|
      results = WebSearchProvider::Brave.new(api_key: "brave-key").search("ruby feeds", max_results: 3)

      call = client.calls.sole
      assert_equal :get, call[:method]
      assert_equal "https://api.search.brave.com/res/v1/web/search?q=ruby+feeds&count=3", call[:url]
      assert_equal "brave-key", call[:headers]["X-Subscription-Token"]
      assert_equal [WebSearchProvider::Result.new(title: "B", url: "https://b.example", snippet: "sb")], results
    end
  end

  test "tavily #search should post the query with a bearer token" do
    body = { results: [{ title: "C", url: "https://c.example", content: "sc" }] }.to_json

    with_client(ok_response(body)) do |client|
      results = WebSearchProvider::Tavily.new(api_key: "tavily-key").search("ruby feeds", max_results: 3)

      call = client.calls.sole
      assert_equal :post, call[:method]
      assert_equal "https://api.tavily.com/search", call[:url]
      assert_equal "Bearer tavily-key", call[:headers]["Authorization"]
      assert_equal({ "query" => "ruby feeds", "max_results" => 3 }, JSON.parse(call[:body]))
      assert_equal [WebSearchProvider::Result.new(title: "C", url: "https://c.example", snippet: "sc")], results
    end
  end

  test "#search should raise ConfigurationError when the key is missing" do
    with_client(ok_response("{}")) do |client|
      assert_raises(WebSearchProvider::ConfigurationError) do
        WebSearchProvider::Serper.new(api_key: nil).search("query")
      end
      assert_empty client.calls
    end
  end

  test "#search should cap results at max_results even when the provider returns more" do
    organic = (1..5).map { |i| { title: "T#{i}", link: "https://#{i}.example", snippet: "s#{i}" } }

    with_client(ok_response({ organic: organic }.to_json)) do
      results = WebSearchProvider::Serper.new(api_key: "key").search("query", max_results: 2)
      assert_equal %w[T1 T2], results.map(&:title)
    end
  end

  test "#search should clamp max_results into the supported range" do
    with_client(ok_response({ organic: [] }.to_json)) do |client|
      WebSearchProvider::Serper.new(api_key: "key").search("query", max_results: 99)
      assert_equal 10, JSON.parse(client.calls.sole[:body]).fetch("num")
    end
  end

  test "#search should raise ProviderError on a non-success HTTP status" do
    with_client(HttpClient::Response.new(status: 429, body: "")) do
      error = assert_raises(WebSearchProvider::ProviderError) do
        WebSearchProvider::Serper.new(api_key: "key").search("query")
      end
      assert_equal "Serper: HTTP 429", error.message
    end
  end

  test "#search should raise AuthError on auth and quota HTTP statuses" do
    [401, 402, 403].each do |status|
      with_client(HttpClient::Response.new(status: status, body: "")) do
        error = assert_raises(WebSearchProvider::AuthError) do
          WebSearchProvider::Serper.new(api_key: "key").search("query")
        end
        assert_equal "Serper: HTTP #{status}", error.message
      end
    end
  end

  test "#search should not raise AuthError for a server error status" do
    with_client(HttpClient::Response.new(status: 500, body: "")) do
      error = assert_raises(WebSearchProvider::ProviderError) do
        WebSearchProvider::Serper.new(api_key: "key").search("query")
      end
      assert_not_kind_of WebSearchProvider::AuthError, error
    end
  end

  test "#search should raise ProviderError on an unparseable response" do
    with_client(ok_response("<html>oops</html>")) do
      error = assert_raises(WebSearchProvider::ProviderError) do
        WebSearchProvider::Serper.new(api_key: "key").search("query")
      end
      assert_match(/unparseable response/, error.message)
    end
  end

  test "#search should raise ProviderError on a transport error" do
    raising = Object.new
    def raising.post(_url, **) = raise(HttpClient::TimeoutError, "timed out")

    HttpClient.stub(:build, ->(**) { raising }) do
      error = assert_raises(WebSearchProvider::ProviderError) do
        WebSearchProvider::Serper.new(api_key: "key").search("query")
      end
      assert_equal "Serper: timed out", error.message
    end
  end

  test "#search should tolerate a payload without results" do
    with_client(ok_response("{}")) do
      assert_empty WebSearchProvider::Serper.new(api_key: "key").search("query")
    end
  end

  test ".estimated_cost_cents should derive fractional cents from the per-1K rate" do
    assert_in_delta 0.1, WebSearchProvider.estimated_cost_cents("serper", 1)
    assert_in_delta 500.0, WebSearchProvider.estimated_cost_cents("brave", 1000)
    assert_in_delta 1.6, WebSearchProvider.estimated_cost_cents(:tavily, 2)
  end

  test ".estimated_cost_cents should estimate zero for an unknown provider" do
    assert_equal 0, WebSearchProvider.estimated_cost_cents("nope", 50)
  end

  test "every registered provider should have a per-1K rate" do
    assert_equal WebSearchProvider::REGISTRY.keys.sort, WebSearchProvider::CENTS_PER_1K_REQUESTS.keys.sort
  end
end
