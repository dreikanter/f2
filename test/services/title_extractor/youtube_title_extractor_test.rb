require "test_helper"

class TitleExtractor::YoutubeTitleExtractorTest < ActiveSupport::TestCase
  def extractor(input, body = nil)
    TitleExtractor::YoutubeTitleExtractor.new(input, body)
  end

  test "#title should read the channel name from the page og:title" do
    body = '<html><head><meta property="og:title" content="Sample Tech Channel"></head></html>'
    assert_equal "Sample Tech Channel", extractor("https://www.youtube.com/@SampleTech", body).title
  end

  test "#title should fall back to the Atom feed title for a feed URL" do
    body = file_fixture("feeds/youtube/feed.xml").read
    url = "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc123def456ghi789jkl"
    assert_equal "Sample Tech Channel", extractor(url, body).title
  end

  test "#title should fall back to the @handle from the URL" do
    assert_equal "@SampleTech", extractor("https://www.youtube.com/@SampleTech").title
  end

  test "#title should return nil when nothing can be derived" do
    assert_nil extractor("https://www.youtube.com/channel/UCabc123def456ghi789jkl").title
  end

  test "#title should swallow parse errors from the page body" do
    body = '<html><head><meta property="og:title" content="Sample Tech Channel"></head></html>'

    Nokogiri::HTML.stub(:parse, ->(*) { raise "boom" }) do
      assert_nil extractor("https://www.youtube.com/channel/UCabc123def456ghi789jkl", body).title
    end
  end

  test "#title should swallow invalid URI errors when deriving a handle" do
    assert_nil extractor("https://www.youtube.com/ bad handle").title
  end

  test "#title should swallow XML SyntaxError when parsing atom feed" do
    url = "https://www.youtube.com/channel/UCabc123def456ghi789jkl"
    Nokogiri.stub(:XML, ->(_) { raise Nokogiri::XML::SyntaxError, "bad xml" }) do
      assert_nil extractor(url, "<broken").title
    end
  end
end
