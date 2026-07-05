require "test_helper"

class Normalizer::LlmNormalizerTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed,
                     user: user,
                     ai_credential: create(:ai_credential, :active, user: user),
                     feed_profile_key: "llm",
                     params: { "prompt" => "https://example.com" })
  end

  def feed_entry(overrides = {})
    raw = {
      "uid" => "https://example.com/post-1",
      "title" => "Post 1",
      "body" => "Hello world",
      "source_url" => "https://example.com/post-1",
      "supplementary" => ["A comment"],
      "images" => ["https://example.com/cover.png"],
      "published_at" => "2026-05-10T10:00:00Z"
    }.merge(overrides)
    FeedEntry.new(
      feed: feed,
      uid: raw["uid"],
      published_at: Time.parse(raw["published_at"]),
      raw_data: raw,
      status: :pending
    )
  end

  test "#normalize should map raw_data fields onto a Post" do
    post = Normalizer::LlmNormalizer.new(feed_entry).normalize

    assert_equal "Hello world", post.content
    assert_equal "https://example.com/post-1", post.source_url
    assert_equal ["https://example.com/cover.png"], post.attachment_urls
    assert_equal ["A comment"], post.comments
    assert_equal "enqueued", post.status
  end

  test "#normalize should reject when source_url is missing" do
    post = Normalizer::LlmNormalizer.new(feed_entry("source_url" => "")).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "missing source_url"
  end

  test "#normalize should reject when content is missing" do
    post = Normalizer::LlmNormalizer.new(feed_entry("body" => "")).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "missing content"
  end

  test "#normalize should reject image-less posts when the feed is images-only" do
    feed.update!(images_only: true)
    post = Normalizer::LlmNormalizer.new(feed_entry("images" => [])).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "no_images"
  end

  test "#normalize should truncate an over-long body to the post content limit" do
    long_body = "word " * 2000 # ~10k chars, well over the 3000 limit
    post = Normalizer::LlmNormalizer.new(feed_entry("body" => long_body)).normalize

    assert_operator post.content.length, :<=, Post::MAX_CONTENT_LENGTH
    assert_equal "enqueued", post.status
  end

  test "#normalize should reject an images-only post whose images were all dropped as unsafe" do
    feed.update!(images_only: true)
    post = Normalizer::LlmNormalizer.new(feed_entry("images" => ["http://127.0.0.1/x.png", "file:///etc/passwd"])).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "no_images"
  end

  test "#normalize should keep only public http(s) attachment URLs" do
    images = [
      "https://cdn.example.com/ok.png",   # public — kept
      "http://127.0.0.1/secret.png",      # loopback — dropped
      "http://169.254.169.254/meta",      # link-local metadata — dropped
      "file:///etc/passwd",               # non-http — dropped
      "/proc/self/environ"                # not a URL — dropped
    ]
    post = Normalizer::LlmNormalizer.new(feed_entry("images" => images)).normalize

    assert_equal ["https://cdn.example.com/ok.png"], post.attachment_urls
  end
end
