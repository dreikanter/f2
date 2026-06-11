require "test_helper"

class Normalizer::TheycantalkNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/theycantalk"
  end

  def processor_class
    Processor::RssProcessor
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::TheycantalkNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should extract the comic image as an attachment" do
    entry = feed_entry(0)

    post = Normalizer::TheycantalkNormalizer.new(entry).normalize

    assert_equal 1, post.attachment_urls.size
    assert_includes post.attachment_urls.first, "64.media.tumblr.com"
  end

  test "#normalize should use the first paragraph as content" do
    entry = feed_entry(0)

    post = Normalizer::TheycantalkNormalizer.new(entry).normalize

    assert_includes post.content, "going out"
  end

  test "#normalize should put remaining paragraphs in comments" do
    entry = feed_entry(0)

    post = Normalizer::TheycantalkNormalizer.new(entry).normalize

    # Entry has only one text paragraph so comments from paragraphs should be empty
    assert_equal [], post.comments
  end
end
