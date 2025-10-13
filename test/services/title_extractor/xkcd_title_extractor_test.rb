require "test_helper"

class TitleExtractor::XkcdTitleExtractorTest < ActiveSupport::TestCase
  def extractor(body)
    response = HttpClient::Response.new(status: 200, body: body)
    TitleExtractor::XkcdTitleExtractor.new("https://xkcd.com/rss.xml", response)
  end

  test "should extract title from xkcd RSS feed" do
    body = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>xkcd.com</title>
          <description>xkcd: A webcomic</description>
        </channel>
      </rss>
    XML
    assert_equal "xkcd.com", extractor(body).title
  end

  test "should return nil for invalid content" do
    assert_nil extractor("not xml").title
  end
end
