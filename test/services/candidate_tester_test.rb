require "test_helper"

class CandidateTesterTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def rss_item(uid: true, published: true)
    <<~ITEM
      <item>
        <title>Hello</title>
        #{'<link>https://example.com/1</link><guid>https://example.com/1</guid>' if uid}
        #{'<pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>' if published}
        <description>Body text</description>
      </item>
    ITEM
  end

  # Valid uid + date so the normalizer doesn't raise, but no content and no URL,
  # so the post is rejected by validation (status :rejected, not :enqueued).
  def rss_item_rejected
    <<~ITEM
      <item>
        <guid>https://example.com/x</guid>
        <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
      </item>
    ITEM
  end

  def rss_feed(items)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Example</title>
          #{items}
        </channel>
      </rss>
    XML
  end

  # Helper name must not start with `test_`, or Minitest runs it as a test.
  def result_for(url, profile_key: "rss")
    CandidateTester.new(user: user, input: url, profile_key: profile_key).call
  end

  test "#call should pass and count posts for a source that yields valid posts" do
    url = "https://example.com/feed.xml"
    stub_request(:get, url).to_return(status: 200, body: rss_feed(rss_item))

    result = result_for(url)
    assert_equal :passed, result.status
    assert_equal 1, result.posts_found
  end

  test "#call should pass an empty-but-valid source with zero posts found" do
    url = "https://example.com/new.xml"
    stub_request(:get, url).to_return(status: 200, body: rss_feed(""))

    result = result_for(url)
    assert_equal :passed, result.status
    assert_equal 0, result.posts_found
  end

  test "#call should pass when at least one entry normalizes even if another fails" do
    # First item has no uid (normalizer rejects it); the second is valid. A
    # single bad entry must not fail an otherwise-working feed.
    url = "https://example.com/mixed.xml"
    stub_request(:get, url).to_return(status: 200, body: rss_feed(rss_item(uid: false) + rss_item))

    result = result_for(url)
    assert_equal :passed, result.status
    assert_equal 1, result.posts_found
  end

  test "#call should fail when no sampled entry normalizes into a valid post" do
    url = "https://example.com/broken.xml"
    stub_request(:get, url).to_return(status: 200, body: rss_feed(rss_item(uid: false)))

    assert_equal :failed, result_for(url).status
  end

  test "#call should fail when entries normalize only into rejected posts" do
    # Parses fine, but the post fails content/URL validation (status :rejected),
    # so it is not a real post and the candidate does not pass.
    url = "https://example.com/rejected.xml"
    stub_request(:get, url).to_return(status: 200, body: rss_feed(rss_item_rejected))

    result = result_for(url)
    assert_equal :failed, result.status
    assert_equal 0, result.posts_found
  end

  test "#call should be unreachable on a server error" do
    url = "https://example.com/down.xml"
    stub_request(:get, url).to_return(status: 503, body: "boom")

    assert_equal :unreachable, result_for(url).status
  end

  test "#call should be unreachable on a transport timeout" do
    url = "https://example.com/slow.xml"
    stub_request(:get, url).to_raise(HttpClient::TimeoutError.new("timed out"))

    assert_equal :unreachable, result_for(url).status
  end

  test "#call should fail when the source is reachable but exposes no feed" do
    # YouTube fetches the page fine, then can't find a feed link — a real
    # compatibility failure, not an unreachable source.
    url = "https://www.youtube.com/@handle"
    stub_request(:get, url).to_return(status: 200, body: "<html><head></head><body>no feed</body></html>")

    assert_equal :failed, result_for(url, profile_key: "youtube").status
  end

  test "#call should reuse a warm http client instead of fetching again" do
    url = "https://example.com/cached.xml"
    stub_request(:get, url).to_return(status: 200, body: rss_feed(rss_item))

    client = HttpClient.build(adapter: HttpClient::CachingAdapter)
    client.get(url) # warm the cache, as matching would before testing

    CandidateTester.new(user: user, input: url, profile_key: "rss", http_client: client).call

    assert_requested :get, url, times: 1
  end
end
