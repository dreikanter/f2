require "test_helper"

class Normalizer::RssNormalizerTest < ActiveSupport::TestCase
  def feed_entry_with_raw_data(raw_data = {})
    default_data = {
      "title" => "<h1>Test Article</h1>",
      "content" => "<p>Test content</p>",
      "summary" => "<p>Test summary</p>",
      "link" => "https://example.com/post",
      "url" => "https://example.com/post",
      "enclosures" => []
    }

    create(:feed_entry, raw_data: default_data.merge(raw_data))
  end

  test "should create valid post from feed entry" do
    feed_entry = feed_entry_with_raw_data

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_instance_of Post, post
    assert_equal feed_entry.feed, post.feed
    assert_equal feed_entry, post.feed_entry
    assert_equal feed_entry.uid, post.uid
    assert_equal feed_entry.published_at, post.published_at
    assert_equal "https://example.com/post", post.source_url
    assert_equal "Test summary", post.content
    assert_equal [], post.attachment_urls
    assert_equal [], post.comments
    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
  end

  test "should extract content from content when summary is missing" do
    feed_entry = feed_entry_with_raw_data("summary" => nil)

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "Test content", post.content
  end

  test "should extract content from title when both summary and content are missing" do
    feed_entry = feed_entry_with_raw_data("summary" => nil, "content" => nil)

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "Test Article", post.content
  end

  test "should clean HTML from content" do
    feed_entry = feed_entry_with_raw_data(
      "summary" => "<p>Paragraph with <strong>bold</strong> and <em>italic</em> text.</p>"
    )

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "Paragraph with bold and italic text.", post.content
  end

  test "should extract source_url from url field when link is missing" do
    feed_entry = feed_entry_with_raw_data("link" => nil, "url" => "https://example.com/url")

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "https://example.com/url", post.source_url
  end

  test "should extract image URLs from enclosures" do
    enclosures = [
      { "type" => "image/jpeg", "url" => "https://example.com/image1.jpg" },
      { "type" => "image/png", "url" => "https://example.com/image2.png" },
      { "type" => "audio/mp3", "url" => "https://example.com/audio.mp3" }
    ]
    feed_entry = feed_entry_with_raw_data("enclosures" => enclosures)

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal ["https://example.com/image1.jpg", "https://example.com/image2.png"], post.attachment_urls
  end

  test "should extract image URLs from content HTML" do
    content_with_images = '<p>Check this out: <img src="https://example.com/content1.jpg" /> and <img src="https://example.com/content2.png" /></p>'
    feed_entry = feed_entry_with_raw_data("content" => content_with_images)

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_includes post.attachment_urls, "https://example.com/content1.jpg"
    assert_includes post.attachment_urls, "https://example.com/content2.png"
  end

  test "should reject post with blank content" do
    feed_entry = feed_entry_with_raw_data(
      "title" => "",
      "content" => "",
      "summary" => ""
    )

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "blank_content"
  end

  test "should reject post with invalid source_url" do
    feed_entry = feed_entry_with_raw_data("link" => "", "url" => "")

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "invalid_source_url"
  end

  test "should reject post with future date" do
    feed_entry = create(:feed_entry, published_at: 1.hour.from_now)

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "future_date"
  end

  test "should handle multiple validation errors" do
    feed_entry = feed_entry_with_raw_data(
      "title" => "",
      "content" => "",
      "summary" => "",
      "link" => "",
      "url" => ""
    )
    feed_entry.update(published_at: 1.hour.from_now)

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "blank_content"
    assert_includes post.validation_errors, "invalid_source_url"
    assert_includes post.validation_errors, "future_date"
  end

  test "should handle invalid URL schemes" do
    feed_entry = feed_entry_with_raw_data("link" => "ftp://example.com/file")

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "invalid_source_url"
  end

  test "should handle malformed URLs" do
    feed_entry = feed_entry_with_raw_data("link" => "not-a-url")

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "invalid_source_url"
  end

  test "should handle URLs that trigger URI::InvalidURIError" do
    # URLs with invalid characters that cause URI.parse to raise URI::InvalidURIError
    invalid_urls = [
      "http://example.com/path with spaces",
      "http://[invalid-ipv6",
      "https://example.com/path\nwith\nnewlines",
      "http://example.com/<invalid>characters"
    ]

    invalid_urls.each do |invalid_url|
      feed_entry = feed_entry_with_raw_data("link" => invalid_url)
      normalizer = Normalizer::RssNormalizer.new(feed_entry)
      post = normalizer.normalize

      assert_equal "rejected", post.status
      assert_includes post.validation_errors, "invalid_source_url"
    end
  end

  test "should reject post with content too long" do
    long_content = "a" * (Post::MAX_CONTENT_LENGTH + 1)
    feed_entry = feed_entry_with_raw_data("summary" => long_content)

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "content_too_long"
  end

  test "should accept post with content at maximum length" do
    max_content = "a" * Post::MAX_CONTENT_LENGTH
    feed_entry = feed_entry_with_raw_data("summary" => max_content)

    normalizer = Normalizer::RssNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "enqueued", post.status
    assert_not_includes post.validation_errors, "content_too_long"
  end
end
