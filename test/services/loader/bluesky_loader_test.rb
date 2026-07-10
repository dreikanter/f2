require "test_helper"

class Loader::BlueskyLoaderTest < ActiveSupport::TestCase
  FEED_BODY = '{"feed":[]}'.freeze

  def mock_client(response: nil, error: nil)
    response ||= HttpClient::Response.new(status: 200, body: FEED_BODY)
    MockHttpClient.new(response: response, error: error)
  end

  def loader(input, http_client: nil)
    feed = create(:feed, feed_profile_key: "bluesky", url: input)
    opts = http_client ? { http_client: http_client } : {}
    Loader::BlueskyLoader.new(feed, opts)
  end

  def expected_url(actor)
    "https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed" \
      "?actor=#{actor}&filter=posts_no_replies"
  end

  test "#load should request the getAuthorFeed endpoint for a bare handle" do
    client = mock_client
    loader("testuser.bsky.social", http_client: client).load
    assert_equal expected_url("testuser.bsky.social"), client.last_request_url
  end

  test "#load should strip a leading @ from the handle" do
    client = mock_client
    loader("@testuser.bsky.social", http_client: client).load
    assert_equal expected_url("testuser.bsky.social"), client.last_request_url
  end

  test "#load should accept a bsky.app profile URL" do
    client = mock_client
    loader("https://bsky.app/profile/testuser.bsky.social", http_client: client).load
    assert_equal expected_url("testuser.bsky.social"), client.last_request_url
  end

  test "#load should accept a schemeless bsky.app profile URL" do
    client = mock_client
    loader("bsky.app/profile/testuser.bsky.social", http_client: client).load
    assert_equal expected_url("testuser.bsky.social"), client.last_request_url
  end

  test "#load should ignore a query string on a profile URL" do
    client = mock_client
    loader("https://bsky.app/profile/testuser.bsky.social?ref=share", http_client: client).load
    assert_equal expected_url("testuser.bsky.social"), client.last_request_url
  end

  test "#load should accept a profile URL with a DID and encode it" do
    client = mock_client
    loader("https://bsky.app/profile/did:plc:abc123", http_client: client).load
    assert_equal expected_url("did%3Aplc%3Aabc123"), client.last_request_url
  end

  test "#load should treat a bare bsky.app input as the official account handle" do
    client = mock_client
    loader("@bsky.app", http_client: client).load
    assert_equal expected_url("bsky.app"), client.last_request_url
  end

  test "#load should send a JSON Accept header" do
    client = mock_client
    loader("testuser.bsky.social", http_client: client).load
    assert_equal "application/json", client.last_headers["Accept"]
  end

  test "#load should return the response body on success" do
    assert_equal FEED_BODY, loader("testuser.bsky.social", http_client: mock_client).load
  end

  test "#load should surface the API error message on HTTP error" do
    body = '{"error":"InvalidRequest","message":"Profile not found"}'
    client = mock_client(response: HttpClient::Response.new(status: 400, body: body))
    error = assert_raises(StandardError) { loader("testuser.bsky.social", http_client: client).load }
    assert_equal "HTTP 400: Profile not found", error.message
  end

  test "#load should raise with the bare status when the error body is not JSON" do
    client = mock_client(response: HttpClient::Response.new(status: 500, body: "oops"))
    error = assert_raises(StandardError) { loader("testuser.bsky.social", http_client: client).load }
    assert_equal "HTTP 500", error.message
  end

  test "#load should raise when the handle is not a domain" do
    error = assert_raises(StandardError) { loader("justname", http_client: mock_client).load }
    assert_match(/Could not determine/, error.message)
  end

  test "#load should raise for a bsky.app URL without a profile path" do
    error = assert_raises(StandardError) { loader("https://bsky.app/search", http_client: mock_client).load }
    assert_match(/Could not determine/, error.message)
  end

  private

  class MockHttpClient
    attr_reader :last_request_url, :last_headers

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
    end

    def get(url, headers: {}, options: {})
      @last_request_url = url
      @last_headers = headers
      raise @error if @error
      @response
    end
  end
end
