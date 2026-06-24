require "test_helper"

class CandidateTesterTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def rss_with_item
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Example</title>
          <item>
            <title>Hello</title>
            <link>https://example.com/1</link>
            <guid>https://example.com/1</guid>
            <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
            <description>Body text</description>
          </item>
        </channel>
      </rss>
    XML
  end

  def empty_rss
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel><title>Brand new</title></channel>
      </rss>
    XML
  end

  # An item with no guid and no link yields a blank uid, which the normalizer
  # rejects: the source was reachable but the profile can't produce posts.
  def rss_missing_uid
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Broken</title>
          <item>
            <title>No identifiers</title>
            <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML
  end

  def test_status_for(url)
    CandidateTester.new(user: user, input: url, profile_key: "rss").test_status
  end

  test "#test_status should be passed for a source that yields a valid post" do
    url = "https://example.com/feed.xml"
    stub_request(:get, url).to_return(status: 200, body: rss_with_item)

    assert_equal :passed, test_status_for(url)
  end

  test "#test_status should be passed for an empty-but-valid source" do
    url = "https://example.com/new.xml"
    stub_request(:get, url).to_return(status: 200, body: empty_rss)

    assert_equal :passed, test_status_for(url)
  end

  test "#test_status should be failed when normalization produces nothing valid" do
    url = "https://example.com/broken.xml"
    stub_request(:get, url).to_return(status: 200, body: rss_missing_uid)

    assert_equal :failed, test_status_for(url)
  end

  test "#test_status should be unreachable when the source can't be fetched" do
    url = "https://example.com/down.xml"
    stub_request(:get, url).to_return(status: 500, body: "boom")

    assert_equal :unreachable, test_status_for(url)
  end

  test "#test_status should reuse a warm http client instead of fetching again" do
    url = "https://example.com/cached.xml"
    stub_request(:get, url).to_return(status: 200, body: rss_with_item)

    client = HttpClient.build(adapter: HttpClient::CachingAdapter)
    client.get(url) # warm the cache, as matching would before testing

    CandidateTester.new(user: user, input: url, profile_key: "rss", http_client: client).test_status

    assert_requested :get, url, times: 1
  end
end
