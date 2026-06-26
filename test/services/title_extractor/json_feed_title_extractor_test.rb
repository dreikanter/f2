require "test_helper"

class TitleExtractor::JsonFeedTitleExtractorTest < ActiveSupport::TestCase
  def extractor(body)
    TitleExtractor::JsonFeedTitleExtractor.new("https://example.com/feed.json", body)
  end

  test "#title should extract the top-level title from a JSON Feed" do
    body = file_fixture("feeds/json_feed/feed.json").read

    assert_equal "Example JSON Feed", extractor(body).title
  end

  test "#title should strip surrounding whitespace" do
    body = '{"version":"https://jsonfeed.org/version/1.1","title":"  Padded Title  "}'

    assert_equal "Padded Title", extractor(body).title
  end

  test "#title should fall back to hostname for a blank body" do
    assert_equal "example.com", extractor("").title
    assert_equal "example.com", extractor(nil).title
  end

  test "#title should fall back to hostname for invalid JSON" do
    assert_equal "example.com", extractor("not valid json").title
  end

  test "#title should fall back to hostname when the feed has no title" do
    body = '{"version":"https://jsonfeed.org/version/1.1","items":[]}'

    assert_equal "example.com", extractor(body).title
  end

  test "#title should fall back to hostname for non-object JSON" do
    assert_equal "example.com", extractor("[1, 2, 3]").title
  end

  test "#title should fall back to nil when the URL has no hostname" do
    e = TitleExtractor::JsonFeedTitleExtractor.new("not-a-url", nil)
    assert_nil e.title
  end
end
