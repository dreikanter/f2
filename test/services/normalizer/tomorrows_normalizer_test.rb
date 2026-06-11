require "test_helper"

class Normalizer::TomorrowsNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/tomorrows"
  end

  def processor_class
    Processor::RssProcessor
  end

  setup do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 200, body: file_fixture("feeds/tomorrows/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::TomorrowsNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use the entry title as content" do
    entry = feed_entry(0)

    post = Normalizer::TomorrowsNormalizer.new(entry).normalize

    assert_equal "The Black Cube - https://365tomorrows.com/2026/06/10/the-black-cube/", post.content
  end

  test "#normalize should include story text as a comment" do
    entry = feed_entry(0)

    post = Normalizer::TomorrowsNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "There was a moment, in his dream"
  end

  test "#normalize should fall back to feed summary when page fetch fails" do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 503)

    entry = feed_entry(0)
    post = Normalizer::TomorrowsNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "Author: Bill Cox"
  end
end
