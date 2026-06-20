require "test_helper"

class Normalizer::LlmNormalizerTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed,
                     user: user,
                     ai_credential: create(:ai_credential, :active, user: user),
                     feed_profile_key: "llm_website_extractor",
                     params: { "url" => "https://example.com" })
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
end
