require "test_helper"

class Normalizer::WebhookNormalizerTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, :webhook)
  end

  def feed_entry(overrides = {})
    raw = {
      "content" => "Look at this",
      "source_url" => "https://example.com/article",
      "images" => ["https://example.com/pic.jpg"],
      "comments" => ["First comment"],
      "uid" => "article-42"
    }.merge(overrides)
    FeedEntry.new(
      feed: feed,
      uid: raw["uid"],
      published_at: Time.utc(2026, 7, 11, 12, 0),
      raw_data: raw,
      status: :pending
    )
  end

  test "#normalize should map the payload onto a Post" do
    post = Normalizer::WebhookNormalizer.new(feed_entry).normalize

    assert_equal "Look at this - https://example.com/article", post.content
    assert_equal "https://example.com/article", post.source_url
    assert_equal ["https://example.com/pic.jpg"], post.attachment_urls
    assert_equal ["First comment"], post.comments
    assert_equal "article-42", post.uid
    assert_equal Time.utc(2026, 7, 11, 12, 0), post.published_at
    assert_equal "enqueued", post.status
  end

  test "#normalize should keep content bare without a source_url" do
    post = Normalizer::WebhookNormalizer.new(feed_entry("source_url" => nil)).normalize

    assert_equal "Look at this", post.content
    assert_nil post.source_url
    assert_equal "enqueued", post.status
  end

  test "#normalize should treat a blank source_url as absent" do
    post = Normalizer::WebhookNormalizer.new(feed_entry("source_url" => "")).normalize

    assert_nil post.source_url
    assert_equal "enqueued", post.status
  end

  test "#normalize should accept images without content" do
    post = Normalizer::WebhookNormalizer.new(
      feed_entry("content" => nil, "source_url" => nil)
    ).normalize

    assert_equal "", post.content
    assert_equal "enqueued", post.status
  end

  test "#normalize should reject a payload with no content and no images" do
    post = Normalizer::WebhookNormalizer.new(
      feed_entry("content" => nil, "source_url" => nil, "images" => [])
    ).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "no_content_or_images"
  end

  test "#normalize should reject a URL-only payload despite the link folding into the body" do
    post = Normalizer::WebhookNormalizer.new(
      feed_entry("content" => nil, "images" => [])
    ).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "no_content_or_images"
  end

  test "#normalize should drop non-public image URLs at the choke point" do
    post = Normalizer::WebhookNormalizer.new(
      feed_entry("images" => ["https://example.com/ok.png", "http://127.0.0.1/secret.png", "/etc/passwd"])
    ).normalize

    assert_equal ["https://example.com/ok.png"], post.attachment_urls
  end

  test "#normalize should clamp over-long comments" do
    post = Normalizer::WebhookNormalizer.new(
      feed_entry("comments" => ["a" * (Post::MAX_COMMENT_LENGTH + 100)])
    ).normalize

    assert_equal Post::MAX_COMMENT_LENGTH, post.comments.first.length
  end

  test "#normalize should truncate content folded with the source link to the FreeFeed limit" do
    post = Normalizer::WebhookNormalizer.new(
      feed_entry("content" => "a" * (Post::MAX_CONTENT_LENGTH + 100))
    ).normalize

    assert_operator post.content.length, :<=, Post::MAX_CONTENT_LENGTH
    assert post.content.end_with?("https://example.com/article")
  end

  test "#normalize should reject an image-less payload on an images-only feed" do
    feed.update!(images_only: true)
    post = Normalizer::WebhookNormalizer.new(feed_entry("images" => [])).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "no_images"
  end
end
