require "test_helper"

class TitleExtractor::TwitterTitleExtractorTest < ActiveSupport::TestCase
  def extractor(input, body = nil)
    TitleExtractor::TwitterTitleExtractor.new(input, body)
  end

  test "#title should use the og:title from the fetched page" do
    body = '<html><head><meta property="og:title" content="X Developers (@XDevelopers) / X"></head></html>'
    assert_equal "X Developers (@XDevelopers) / X", extractor("https://x.com/XDevelopers", body).title
  end

  test "#title should fall back to the @handle from an x.com URL" do
    assert_equal "@XDevelopers", extractor("https://x.com/XDevelopers").title
  end

  test "#title should fall back to the @handle from a twitter.com URL" do
    assert_equal "@XDevelopers", extractor("https://twitter.com/XDevelopers").title
  end

  test "#title should fall back to the @handle from an @handle input" do
    assert_equal "@XDevelopers", extractor("@XDevelopers").title
  end

  test "#title should fall back to the @handle from a bare handle" do
    assert_equal "@XDevelopers", extractor("XDevelopers").title
  end
end
