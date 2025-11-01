require "test_helper"

class ProfileMatcher::RssProfileMatcherTest < ActiveSupport::TestCase
  def matcher(body)
    response = HttpClient::Response.new(status: 200, body: body)
    ProfileMatcher::RssProfileMatcher.new("https://example.com/feed.xml", response)
  end

  test "#match? should match RSS 2.0 feeds" do
    body = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
        </channel>
      </rss>
    XML

    assert matcher(body).match?
  end

  test "#match? should match Atom feeds" do
    body = <<~XML
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test Feed</title>
      </feed>
    XML

    assert matcher(body).match?
  end

  test "#match? should match RSS 1.0 (RDF) feeds" do
    body = <<~XML
      <?xml version="1.0"?>
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <channel>
          <title>Test Feed</title>
        </channel>
      </rdf:RDF>
    XML

    assert matcher(body).match?
  end

  test "#match? should not match non-RSS content" do
    assert_not matcher("<html><body>Not a feed</body></html>").match?
  end

  test "#match? should handle blank response body" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end

  test "#match? should be case insensitive" do
    assert matcher("<RSS version='2.0'><channel></channel></RSS>").match?
    assert matcher("<FEED></FEED>").match?
  end
end
