require "test_helper"

class FeedProfileDetectorTest < ActiveSupport::TestCase
  test "DETECTION_ORDER contains only existing profile names" do
    FeedProfileDetector::DETECTION_ORDER.each do |profile_key|
      assert FeedProfile.exists?(profile_key), "Profile '#{profile_key}' in DETECTION_ORDER does not exist"
    end
  end

  def detector(url, body)
    response = HttpClient::Response.new(status: 200, body: body)
    FeedProfileDetector.new(url, response)
  end

  def rss_feed_body
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>A test feed</description>
        </channel>
      </rss>
    XML
  end

  test "should detect xkcd profile for xkcd.com URLs" do
    assert_equal "xkcd", detector("https://xkcd.com/rss.xml", rss_feed_body).detect
  end

  test "should detect rss profile for generic RSS feeds" do
    assert_equal "rss", detector("https://example.com/feed.xml", rss_feed_body).detect
  end

  test "should prefer xkcd over rss for xkcd.com URLs" do
    # xkcd URLs should match xkcd profile even though they contain RSS content
    assert_equal "xkcd", detector("https://xkcd.com/atom.xml", rss_feed_body).detect
  end

  test "should return nil for non-matching content" do
    html = "<html><body>Not a feed</body></html>"
    assert_nil detector("https://example.com/page.html", html).detect
  end

  test "should return nil for blank response body" do
    assert_nil detector("https://example.com/feed.xml", "").detect
  end

  test "should detect rss profile for Atom feeds" do
    atom_body = <<~XML
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Atom Feed</title>
      </feed>
    XML
    assert_equal "rss", detector("https://example.com/atom.xml", atom_body).detect
  end

  test "should detect rss profile for RSS 1.0 feeds" do
    rdf_body = <<~XML
      <?xml version="1.0"?>
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <channel>
          <title>RDF Feed</title>
        </channel>
      </rdf:RDF>
    XML
    assert_equal "rss", detector("https://example.com/rss.rdf", rdf_body).detect
  end

  test "should handle invalid URLs gracefully" do
    # Invalid URL still matches RSS if response body contains RSS content
    assert_equal "rss", detector("not a url", rss_feed_body).detect
  end

  test "should detect profiles in correct order (specific before generic)" do
    # xkcd matcher should be checked before rss matcher
    # This ensures xkcd.com feeds get the xkcd profile, not generic rss
    xkcd_url = "https://xkcd.com/rss.xml"
    result = detector(xkcd_url, rss_feed_body).detect
    assert_equal "xkcd", result, "xkcd profile should be detected before rss profile"
  end
end
