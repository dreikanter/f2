require "test_helper"

class TitleExtractor::RssTitleExtractorTest < ActiveSupport::TestCase
  def extractor(body)
    TitleExtractor::RssTitleExtractor.new("https://example.com/feed.xml", body)
  end

  test "#title should extract title from RSS 2.0 feed" do
    body = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>My RSS Feed</title>
          <description>A test feed</description>
        </channel>
      </rss>
    XML
    assert_equal "My RSS Feed", extractor(body).title
  end

  test "#title should strip whitespace from title" do
    body = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>
            Padded Title
          </title>
        </channel>
      </rss>
    XML
    assert_equal "Padded Title", extractor(body).title
  end

  test "#title should return nil for blank response body" do
    assert_nil extractor("").title
    assert_nil extractor(nil).title
  end

  test "#title should return nil for invalid XML" do
    assert_nil extractor("not valid xml").title
  end

  test "#title should return nil for XML without title" do
    body = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <description>No title here</description>
        </channel>
      </rss>
    XML
    assert_nil extractor(body).title
  end

  test "#title should return nil for non-feed XML" do
    body = <<~XML
      <?xml version="1.0"?>
      <document>
        <title>This is not a feed</title>
      </document>
    XML
    assert_nil extractor(body).title
  end

  test "#title should extract title from Atom feed" do
    body = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>My Atom Feed</title>
      </feed>
    XML
    assert_equal "My Atom Feed", extractor(body).title
  end

  test "#title should extract title from YouTube Atom feed" do
    body = file_fixture("feeds/youtube/feed.xml").read
    assert_equal "Sample Tech Channel", extractor(body).title
  end
end
