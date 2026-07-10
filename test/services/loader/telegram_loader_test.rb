require "test_helper"

class Loader::TelegramLoaderTest < ActiveSupport::TestCase
  PREVIEW_BODY = '<html><section class="tgme_channel_history js-message_history"></section></html>'
  INFO_PAGE_BODY = '<html><div class="tgme_page_extra">12 subscribers</div></html>'

  def mock_client(response: nil, error: nil)
    response ||= HttpClient::Response.new(status: 200, body: PREVIEW_BODY)
    MockHttpClient.new(response: response, error: error)
  end

  def loader(input, http_client: nil)
    feed = create(:feed, feed_profile_key: "telegram", url: input)
    opts = http_client ? { http_client: http_client } : {}
    Loader::TelegramLoader.new(feed, opts)
  end

  test "#load should fetch the t.me/s preview for a bare channel name" do
    client = mock_client
    loader("examplechannel", http_client: client).load
    assert_equal "https://t.me/s/examplechannel", client.last_request_url
  end

  test "#load should strip a leading @ from the channel handle" do
    client = mock_client
    loader("@examplechannel", http_client: client).load
    assert_equal "https://t.me/s/examplechannel", client.last_request_url
  end

  test "#load should accept a schemeless t.me URL" do
    client = mock_client
    loader("t.me/examplechannel", http_client: client).load
    assert_equal "https://t.me/s/examplechannel", client.last_request_url
  end

  test "#load should accept a full t.me channel URL" do
    client = mock_client
    loader("https://t.me/examplechannel", http_client: client).load
    assert_equal "https://t.me/s/examplechannel", client.last_request_url
  end

  test "#load should accept a t.me/s preview URL" do
    client = mock_client
    loader("https://t.me/s/examplechannel", http_client: client).load
    assert_equal "https://t.me/s/examplechannel", client.last_request_url
  end

  test "#load should send a desktop User-Agent header" do
    client = mock_client
    loader("examplechannel", http_client: client).load
    assert_match %r{Mozilla/5\.0}, client.last_headers["User-Agent"]
  end

  test "#load should return the response body on success" do
    assert_equal PREVIEW_BODY, loader("examplechannel", http_client: mock_client).load
  end

  test "#load should raise on HTTP error" do
    client = mock_client(response: HttpClient::Response.new(status: 404, body: ""))
    error = assert_raises(StandardError) { loader("examplechannel", http_client: client).load }
    assert_equal "HTTP 404", error.message
  end

  test "#load should raise when the channel cannot be determined" do
    error = assert_raises(StandardError) { loader("https://t.me/", http_client: mock_client).load }
    assert_match(/Could not determine/, error.message)
  end

  test "#load should raise when the channel has no public web preview" do
    client = mock_client(response: HttpClient::Response.new(status: 200, body: INFO_PAGE_BODY))
    error = assert_raises(Loader::Error) { loader("examplechannel", http_client: client).load }
    assert_match(/No public web preview for examplechannel/, error.message)
  end

  test "#load should accept a preview page with no posts yet" do
    assert_equal PREVIEW_BODY, loader("examplechannel", http_client: mock_client).load
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
