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

  test "#normalize_attachment_urls should return empty array by default" do
    result = normalizer.send(:normalize_attachment_urls)
    assert_equal [], result
  end

  test "#normalize_comments should return empty array by default" do
    result = normalizer.send(:normalize_comments)
    assert_equal [], result
  end

  test "#validate_universal_post_shape! should accept a post with all required fields" do
    post = Post.new(
      feed: feed_entry.feed,
      feed_entry: feed_entry,
      source_url: "https://example.com/post/1",
      published_at: Time.current,
      uid: "uid-1"
    )

    assert_nothing_raised { normalizer.validate_universal_post_shape!(post) }
  end

  test "#validate_universal_post_shape! should accept a post with blank source_url" do
    # source_url is intentionally not in the strict shape check — profiles
    # may emit "" for it (e.g., RSS rejecting an over-length URL); content
    # validation handles the rejection.
    post = Post.new(
      feed: feed_entry.feed,
      feed_entry: feed_entry,
      source_url: "",
      published_at: Time.current,
      uid: "uid-1"
    )

    assert_nothing_raised { normalizer.validate_universal_post_shape!(post) }
  end

  test "#validate_universal_post_shape! should raise when uid is missing" do
    post = Post.new(
      feed: feed_entry.feed,
      feed_entry: feed_entry,
      source_url: "https://example.com/post/1",
      published_at: Time.current,
      uid: nil
    )

    error = assert_raises(Normalizer::UniversalPostShapeError) do
      normalizer.validate_universal_post_shape!(post)
    end
    assert_includes error.message, "uid"
  end

  test "#validate_universal_post_shape! should raise when published_at is missing" do
    post = Post.new(
      feed: feed_entry.feed,
      feed_entry: feed_entry,
      source_url: "https://example.com/post/1",
      published_at: nil,
      uid: "uid-1"
    )

    error = assert_raises(Normalizer::UniversalPostShapeError) do
      normalizer.validate_universal_post_shape!(post)
    end
    assert_includes error.message, "published_at"
  end

  test "#validate_universal_post_shape! should list every missing field in one error" do
    post = Post.new(feed: feed_entry.feed, feed_entry: feed_entry, uid: nil, published_at: nil)

    error = assert_raises(Normalizer::UniversalPostShapeError) do
      normalizer.validate_universal_post_shape!(post)
    end
    assert_includes error.message, "uid"
    assert_includes error.message, "published_at"
  end
end
