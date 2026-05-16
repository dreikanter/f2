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
