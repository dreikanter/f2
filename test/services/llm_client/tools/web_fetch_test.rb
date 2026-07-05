require "test_helper"

class LlmClient::Tools::WebFetchTest < ActiveSupport::TestCase
  def tool = LlmClient::Tools::WebFetch.new

  # Records every URL the tool tries to fetch, so blocked URLs can be asserted
  # to never reach the network.
  class RecordingClient
    attr_reader :requested

    def initialize(response)
      @response = response
      @requested = []
    end

    def get(url)
      @requested << url
      @response
    end
  end

  def ok_response(body = "<h1>Hi</h1><p>body</p>")
    HttpClient::Response.new(status: 200, body: body)
  end

  def with_client(response)
    client = RecordingClient.new(response)
    HttpClient.stub(:build, ->(**) { client }) { yield client }
  end

  test "#execute should fetch a public URL and return stripped, capped text" do
    with_client(ok_response("<h1>Title</h1>  <p>Body   text</p>")) do
      result = tool.execute(url: "https://example.com/post")
      assert_equal "Title Body text", result[:content]
    end
  end

  test "#execute should refuse non-http schemes without making a request" do
    with_client(ok_response) do |client|
      assert_match(/Refused/, tool.execute(url: "ftp://example.com")[:error])
      assert_match(/Refused/, tool.execute(url: "file:///etc/passwd")[:error])
      assert_empty client.requested
    end
  end

  test "#execute should refuse localhost and private/link-local hosts" do
    with_client(ok_response) do |client|
      %w[
        http://localhost/x http://127.0.0.1/x http://10.1.2.3/ http://192.168.0.1/
        http://172.16.5.5/ http://169.254.169.254/latest/meta-data/ http://[::1]/
      ].each do |url|
        assert_match(/Refused/, tool.execute(url: url)[:error], url)
      end
      assert_empty client.requested
    end
  end

  test "#execute should refuse a URL carrying credentials" do
    with_client(ok_response) do |client|
      assert_match(/Refused/, tool.execute(url: "https://user:pass@example.com/")[:error])
      assert_empty client.requested
    end
  end

  test "#execute should report a non-success HTTP status" do
    with_client(HttpClient::Response.new(status: 404, body: "")) do
      assert_equal "HTTP 404", tool.execute(url: "https://example.com/missing")[:error]
    end
  end

  test "#execute should surface transport errors as an error result" do
    raising = Object.new
    def raising.get(_url) = raise(HttpClient::TimeoutError, "timed out")

    HttpClient.stub(:build, ->(**) { raising }) do
      assert_equal "timed out", tool.execute(url: "https://example.com/")[:error]
    end
  end
end
