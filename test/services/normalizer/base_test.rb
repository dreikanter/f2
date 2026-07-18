require "test_helper"

class Normalizer::BaseTest < ActiveSupport::TestCase
  def feed_entry
    @feed_entry ||= create(:feed_entry)
  end

  def normalizer
    @normalizer ||= Normalizer::Base.new(feed_entry)
  end

  test "#initialize should run without errors" do
    assert_nothing_raised do
      Normalizer::Base.new(feed_entry)
    end
  end

  test "#normalize_source_url should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      normalizer.send(:normalize_source_url)
    end
    assert_equal "Subclasses must implement #normalize_source_url", error.message
  end

  test "#normalize_content should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      normalizer.send(:normalize_content)
    end
    assert_equal "Subclasses must implement #normalize_content", error.message
  end

  test "#normalize_published_at should fall back to now for an undated entry" do
    freeze_time do
      assert_equal Time.current, normalizer.send(:normalize_published_at, nil)
    end
  end

  test "#normalize_published_at should clamp future timestamps to now" do
    freeze_time do
      assert_equal Time.current, normalizer.send(:normalize_published_at, 1.hour.from_now)
    end
  end

  test "#normalize_published_at should keep a past timestamp" do
    past = 3.days.ago
    assert_equal past, normalizer.send(:normalize_published_at, past)
  end

  test "#normalize_attachment_urls should return empty array by default" do
    result = normalizer.send(:normalize_attachment_urls)
    assert_equal [], result
  end

  test "#normalize_comments should return empty array by default" do
    result = normalizer.send(:normalize_comments)
    assert_equal [], result
  end

  test "#comments should truncate entries longer than the FreeFeed limit" do
    long_comment = "a" * (Post::MAX_COMMENT_LENGTH + 50)
    subclass = Class.new(Normalizer::Base) do
      def self.name = "Normalizer::LongCommentNormalizer"
      def normalize_comments = raw_data["comments"]
    end
    entry = create(:feed_entry, raw_data: { "comments" => [long_comment, "short"] })

    result = subclass.new(entry).send(:comments)

    assert_equal Post::MAX_COMMENT_LENGTH, result.first.length
    assert result.first.end_with?("…")
    assert_equal "short", result.last
  end

  test "#normalize should reject image-less posts for images-only feeds" do
    subclass = Class.new(Normalizer::Base) do
      def self.name = "Normalizer::TextOnlyNormalizer"
      def normalize_source_url = "https://example.com/post"
      def normalize_content = "Some text without images"
    end
    feed = create(:feed, images_only: true)
    entry = create(:feed_entry, feed: feed)

    post = subclass.new(entry).normalize

    assert post.rejected?
    assert_includes post.validation_errors, "no_images"
  end

  test "#normalize should enqueue posts with images for images-only feeds" do
    subclass = Class.new(Normalizer::Base) do
      def self.name = "Normalizer::ImageNormalizer"
      def normalize_source_url = "https://example.com/post"
      def normalize_content = "Some text"
      def normalize_attachment_urls = ["https://example.com/photo.jpg"]
    end
    feed = create(:feed, images_only: true)
    entry = create(:feed_entry, feed: feed)

    post = subclass.new(entry).normalize

    assert post.enqueued?
    assert_empty post.validation_errors
  end

  test "#normalize should raise MissingUidError when the subclass produces a blank uid" do
    subclass = Class.new(Normalizer::Base) do
      def self.name = "Normalizer::NoUidNormalizer"
      def build_post
        Post.new(feed: feed_entry.feed, feed_entry: feed_entry, source_url: "", published_at: Time.current, uid: nil)
      end
    end

    error = assert_raises(Normalizer::MissingUidError) { subclass.new(feed_entry).normalize }
    assert_includes error.message, "Normalizer::NoUidNormalizer"
  end

  test "#normalize should raise MissingPublishedAtError when the subclass produces a nil published_at" do
    subclass = Class.new(Normalizer::Base) do
      def self.name = "Normalizer::NoPublishedAtNormalizer"
      def build_post
        Post.new(feed: feed_entry.feed, feed_entry: feed_entry, source_url: "", published_at: nil, uid: "uid-1")
      end
    end

    error = assert_raises(Normalizer::MissingPublishedAtError) { subclass.new(feed_entry).normalize }
    assert_includes error.message, "Normalizer::NoPublishedAtNormalizer"
  end
end
