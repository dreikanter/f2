require "test_helper"

class Normalizer::JsonFeedNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/json_feed"
  end

  def fixture_file
    "feed.json"
  end

  def processor_class
    Processor::JsonFeedProcessor
  end

  test "#normalize should create a valid post from a feed entry" do
    normalizer = Normalizer::JsonFeedNormalizer.new(feed_entry(0))
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should extract inline content images as attachments" do
    post = Normalizer::JsonFeedNormalizer.new(feed_entry(0)).normalize

    assert_equal ["https://example.com/inline.jpg"], post.attachment_urls
    assert_equal "enqueued", post.status
  end

  test "#normalize should prefer full content over the summary blurb" do
    post = Normalizer::JsonFeedNormalizer.new(feed_entry(0)).normalize

    assert_includes post.content, "Hello, world!"
    assert_not_includes post.content, "short summary"
  end

  test "#normalize should fall back to the summary when content is blank" do
    entry = create(:feed_entry, raw_data: {
      "summary" => "Just a blurb.",
      "content" => "",
      "link" => "https://example.com/blurb"
    })

    post = Normalizer::JsonFeedNormalizer.new(entry).normalize

    assert_equal "Just a blurb. - https://example.com/blurb", post.content
  end

  test "#normalize should attach image and image-typed attachment enclosures" do
    photo = feed_entries.find { |entry| entry.uid == "https://example.com/photo-post" }
    photo.save!

    post = Normalizer::JsonFeedNormalizer.new(photo).normalize

    assert_equal [
      "https://example.com/main-photo.jpg",
      "https://example.com/banner.jpg",
      "https://example.com/gallery.png"
    ], post.attachment_urls
  end

  test "#normalize should use the item url as the source url" do
    post = Normalizer::JsonFeedNormalizer.new(feed_entry(0)).normalize

    assert_equal "https://example.com/first-post", post.source_url
  end
end
