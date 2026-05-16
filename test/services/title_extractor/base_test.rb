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
end
