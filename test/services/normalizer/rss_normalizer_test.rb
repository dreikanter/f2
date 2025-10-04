require "test_helper"

class Normalizer::RssNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/rss"
  end

  def processor_class
    Processor::RssProcessor
  end

  test "should create valid post from feed entry" do
    entry = feed_entry(0)

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "should accept post with URL even when text content is blank" do
    entry = create(:feed_entry, raw_data: {
      "title" => "",
      "content" => "",
      "summary" => "",
      "link" => "https://example.com/blank"
    })

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "https://example.com/blank", post.content
    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
  end

  test "should normalize future publication date to current date" do
    future_time = 1.hour.from_now
    entry = create(:feed_entry, published_at: future_time)

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
    assert_equal Time.current.to_date, post.published_at.to_date
    assert post.published_at <= Time.current
  end

  test "should truncate content that is too long" do
    long_content = "a" * (Post::MAX_CONTENT_LENGTH + 1)

    entry = create(:feed_entry, raw_data: {
      "summary" => long_content,
      "link" => "https://example.com/long"
    })

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
    assert post.content.length <= Post::MAX_CONTENT_LENGTH
    assert post.content.ends_with?("https://example.com/long")
  end

  test "should reject post when URL is too long" do
    very_long_url = "https://example.com/" + ("a" * Post::MAX_URL_LENGTH)

    entry = create(:feed_entry, raw_data: {
      "summary" => "Test content",
      "link" => very_long_url
    })

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "", post.source_url
    assert_equal "Test content", post.content
    assert post.content.length <= Post::MAX_CONTENT_LENGTH
    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "url_too_long"
  end

  test "should reject post when URL is too long and content is blank" do
    very_long_url = "https://example.com/" + ("a" * Post::MAX_URL_LENGTH)

    entry = create(:feed_entry, raw_data: {
      "title" => "",
      "content" => "",
      "summary" => "",
      "link" => very_long_url
    })

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "", post.source_url
    assert_equal "", post.content
    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "url_too_long"
    assert_includes post.validation_errors, "no_content_or_images"
  end
end
