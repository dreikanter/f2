require "test_helper"

class FeedProfileDetectorTest < ActiveSupport::TestCase
  test "DETECTION_ORDER contains only valid matcher classes" do
    FeedProfileDetector::DETECTION_ORDER.each do |matcher_class_name|
      assert_nothing_raised do
        matcher_class_name.constantize
      end

      error_message = "#{matcher_class_name} should inherit from ProfileMatcher::Base"
      assert matcher_class_name.constantize < ProfileMatcher::Base, error_message
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
    actual = detector("https://xkcd.com/rss.xml", rss_feed_body).detect
    assert_equal ProfileMatcher::XkcdProfileMatcher, actual
  end

  test "should detect rss profile for generic RSS feeds" do
    actual = detector("https://example.com/feed.xml", rss_feed_body).detect
    assert_equal ProfileMatcher::RssProfileMatcher, actual
  end

  test "should prefer xkcd over rss for xkcd.com URLs" do
    actual = detector("https://xkcd.com/atom.xml", rss_feed_body).detect
    assert_equal ProfileMatcher::XkcdProfileMatcher, actual
  end

  test "should return nil for non-matching content" do
    html = "<html><body>Not a feed</body></html>"
    assert_nil detector("https://example.com/page.html", html).detect
  end

  test "should return nil for blank response body" do
    assert_nil detector("https://example.com/feed.xml", "").detect
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

    actual = detector("https://example.com/rss.rdf", rdf_body).detect
    assert_equal "ProfileMatcher::RssProfileMatcher", actual
  end

  test "should handle invalid URLs gracefully" do
    actual = detector("not a url", rss_feed_body).detect
    assert_equal ProfileMatcher::RssProfileMatcher, actual
  end

  test "should detect profiles in correct order (specific before generic)" do
    xkcd_url = "https://xkcd.com/rss.xml"
    result = detector(xkcd_url, rss_feed_body).detect
    assert_equal "ProfileMatcher::XkcdProfileMatcher", result
  end
end
