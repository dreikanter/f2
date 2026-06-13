require "test_helper"

class Normalizer::RedditNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/reddit"
  end

  def processor_class
    Processor::RssProcessor
  end

  test "#normalize should match the expected normalization result for a text post" do
    entry = feed_entry(0)

    normalizer = Normalizer::RedditNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use title only for a link post with no body" do
    entry = feed_entry(1)

    normalizer = Normalizer::RedditNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
    assert post.content.start_with?("Ruby 3.4 Released")
    assert_not_includes post.content, "submitted by"
    assert_not_includes post.content, "/u/rubydev"
  end

  test "#normalize should strip 'submitted by' footer from text posts" do
    entry = feed_entry(0)

    normalizer = Normalizer::RedditNormalizer.new(entry)
    post = normalizer.normalize

    assert_not_includes post.content, "submitted by"
    assert_not_includes post.content, "/u/techuser"
  end

  test "#normalize should skip preview-CDN image attachments" do
    entry = feed_entry(2)

    normalizer = Normalizer::RedditNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal [], post.attachment_urls
  end

  test "#normalize should include Reddit permalink as source URL" do
    entry = feed_entry(0)

    normalizer = Normalizer::RedditNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "https://www.reddit.com/r/programming/comments/abc123/ask_rprogramming_what_are_you_working_on/",
                 post.source_url
  end
end
