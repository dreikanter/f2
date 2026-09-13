require "test_helper"

class Normalizer::RedditNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  test "#normalize should read Reddit Atom content through the actual RSS processor" do
    sample_feed = build(:feed, feed_profile_key: "reddit", url: "https://example.com/discussions")
    entry = Processor::RssProcessor.new(sample_feed, file_fixture("feeds/reddit/content.atom").read).process.entries.sole

    post = Normalizer::RedditNormalizer.new(entry).normalize

    assert_equal "Sample article\n\nSample discussion body. - https://example.com/discussion", post.content
    assert_equal ["https://example.org/article"], post.comments
    assert_equal Time.utc(2026, 9, 9, 10), entry.published_at
  end

  test "#normalize should preserve the article destination separately from the discussion" do
    entry = build(:feed_entry, raw_data: {
      "title" => "Sample story",
      "link" => "https://example.com/discussion",
      "summary" => '<a href="https://example.org/story">[link]</a> <a href="https://example.com/discussion">[comments]</a>'
    })

    post = Normalizer::RedditNormalizer.new(entry).normalize

    assert_equal "Sample story - https://example.com/discussion", post.content
    assert_equal ["https://example.org/story"], post.comments
  end

  test "#normalize should omit duplicate discussion links and unsafe article URLs" do
    entry = build(:feed_entry, raw_data: {
      "link" => "https://example.com/discussion",
      "summary" => '<a href="https://example.com/discussion">[link]</a> <a href="javascript:alert(1)">[link]</a>'
    })

    post = Normalizer::RedditNormalizer.new(entry).normalize

    assert_empty post.comments
  end

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

  test "#normalize should decode HTML character references in the title" do
    entry = feed_entry(3)

    normalizer = Normalizer::RedditNormalizer.new(entry)
    post = normalizer.normalize

    assert post.content.start_with?("It’s a “quoted” title & more\n\nHere’s the body text.")
  end

  test "#normalize should include Reddit permalink as source URL" do
    entry = feed_entry(0)

    normalizer = Normalizer::RedditNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "https://www.reddit.com/r/programming/comments/abc123/ask_rprogramming_what_are_you_working_on/",
                 post.source_url
  end
end
