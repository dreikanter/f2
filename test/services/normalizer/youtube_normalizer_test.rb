require "test_helper"

class Normalizer::YoutubeNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/youtube"
  end

  def processor_class
    Processor::YoutubeProcessor
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::YoutubeNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use video title as content" do
    entry = create(:feed_entry, raw_data: {
      "title" => "My Video",
      "link" => "https://www.youtube.com/watch?v=abc123"
    })

    normalizer = Normalizer::YoutubeNormalizer.new(entry)
    post = normalizer.normalize

    assert_includes post.content, "My Video"
  end

  test "#normalize should not attach thumbnail" do
    entry = create(:feed_entry, raw_data: {
      "title" => "Video",
      "link" => "https://www.youtube.com/watch?v=abc123",
      "thumbnail" => "https://i.ytimg.com/vi/abc123/hqdefault.jpg"
    })

    normalizer = Normalizer::YoutubeNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal [], post.attachment_urls
  end

  test "#normalize should include description as comment" do
    entry = create(:feed_entry, raw_data: {
      "title" => "Video",
      "link" => "https://www.youtube.com/watch?v=abc123",
      "content" => "This is a description."
    })

    normalizer = Normalizer::YoutubeNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal ["This is a description."], post.comments
  end

  test "#normalize should truncate a description that exceeds the comment limit" do
    long_description = "a" * (Post::MAX_COMMENT_LENGTH + 100)
    entry = create(:feed_entry, raw_data: {
      "title" => "Video",
      "link" => "https://www.youtube.com/watch?v=abc123",
      "content" => long_description
    })

    normalizer = Normalizer::YoutubeNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal 1, post.comments.length
    assert_equal Post::MAX_COMMENT_LENGTH, post.comments.first.length
    assert post.comments.first.end_with?("…")
    assert post.enqueued?, "a truncated comment must still let the post enqueue"
  end

  test "#normalize should produce empty comments when description is blank" do
    entry = create(:feed_entry, raw_data: {
      "title" => "Video",
      "link" => "https://www.youtube.com/watch?v=abc123"
    })

    normalizer = Normalizer::YoutubeNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal [], post.comments
  end

  test "#normalize should produce empty attachment_urls when no thumbnail" do
    entry = create(:feed_entry, raw_data: {
      "title" => "Video",
      "link" => "https://www.youtube.com/watch?v=abc123"
    })

    normalizer = Normalizer::YoutubeNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal [], post.attachment_urls
  end

  test "#normalize should work with raw_data produced directly by YoutubeProcessor" do
    feed = create(:feed, url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc123")
    sample_feed_xml = file_fixture("feeds/youtube/feed.xml").read

    processor = Processor::YoutubeProcessor.new(feed, sample_feed_xml)
    processor_entry = processor.process.first

    temp_entry = FeedEntry.new(
      uid: processor_entry.uid,
      published_at: processor_entry.published_at,
      raw_data: processor_entry.raw_data,
      feed: feed
    )

    normalizer = Normalizer::YoutubeNormalizer.new(temp_entry)
    post = normalizer.normalize

    assert_includes post.content, "Getting Started with Ruby on Rails"
    assert_equal [], post.attachment_urls
    assert_equal 1, post.comments.length
    assert_includes post.comments.first, "beginner-friendly introduction"
  end
end
