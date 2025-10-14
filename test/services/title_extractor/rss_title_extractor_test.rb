require "test_helper"

class TitleExtractor::RssTitleExtractorTest < ActiveSupport::TestCase
  def extractor(body)
    response = HttpClient::Response.new(status: 200, body: body)
    TitleExtractor::RssTitleExtractor.new("https://example.com/feed.xml", response)
  end

  test "should extract title from RSS 2.0 feed" do
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

  test "should strip whitespace from title" do
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

  test "should return nil for blank response body" do
    assert_nil extractor("").title
    assert_nil extractor(nil).title
  end

  test "should return nil for invalid XML" do
    assert_nil extractor("not valid xml").title
  end

  test "should return nil for XML without title" do
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

  test "should return nil for non-feed XML" do
    body = <<~XML
      <?xml version="1.0"?>
      <document>
        <title>This is not a feed</title>
      </document>
    XML
    assert_nil extractor(body).title
  end
end
