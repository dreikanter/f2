require "test_helper"

class TitleExtractor::BaseTest < ActiveSupport::TestCase
  def extractor
    @extractor ||= TitleExtractor::Base.new("https://example.com", "<rss/>")
  end

  test "#initialize should expose input and fetched_body" do
    assert_equal "https://example.com", extractor.input
    assert_equal "<rss/>", extractor.fetched_body
  end

  test "#initialize should default fetched_body to nil" do
    bare = TitleExtractor::Base.new("https://example.com")
    assert_nil bare.fetched_body
  end

  test "#title should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      extractor.title
    end
    assert_equal "Subclasses must implement #title", error.message
  end

  test "#hostname_from_url should return hostname without www prefix" do
    e = TitleExtractor::Base.new("https://www.example.com/feed.xml")
    assert_equal "example.com", e.send(:hostname_from_url)
  end

  test "#hostname_from_url should return hostname as-is when no www prefix" do
    e = TitleExtractor::Base.new("https://feeds.example.com/rss")
    assert_equal "feeds.example.com", e.send(:hostname_from_url)
  end

  test "#hostname_from_url should return nil for invalid URL" do
    e = TitleExtractor::Base.new("not a url")
    assert_nil e.send(:hostname_from_url)
  end
end
