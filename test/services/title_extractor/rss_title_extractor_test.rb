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

  test "#title should fall back to hostname for blank response body" do
    assert_equal "example.com", extractor("").title
    assert_equal "example.com", extractor(nil).title
  end

  test "#title should fall back to hostname for invalid XML" do
    assert_equal "example.com", extractor("not valid xml").title
  end

  test "#title should fall back to hostname when feed has no title" do
    body = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <description>No title here</description>
        </channel>
      </rss>
    XML
    assert_equal "example.com", extractor(body).title
  end

  test "#title should fall back to hostname for non-feed XML" do
    body = <<~XML
      <?xml version="1.0"?>
      <document>
        <title>This is not a feed</title>
      </document>
    XML
    assert_equal "example.com", extractor(body).title
  end

  test "#title should extract title from RSS 1.0 (RDF) feed" do
    body = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rdf:RDF
          xmlns="http://purl.org/rss/1.0/"
          xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <channel rdf:about="https://example.com/feed">
          <title>My RDF Feed</title>
        </channel>
      </rdf:RDF>
    XML
    assert_equal "My RDF Feed", extractor(body).title
  end

  test "#title should fall back to nil when URL has no hostname" do
    e = TitleExtractor::RssTitleExtractor.new("not-a-url", nil)
    assert_nil e.title
  end

  test "#title should fall back to hostname when XML parser raises SyntaxError" do
    Nokogiri.stub(:XML, ->(_) { raise Nokogiri::XML::SyntaxError, "bad xml" }) do
      assert_equal "example.com", extractor("<broken").title
    end
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
