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

  test "#normalize should include thumbnail as attachment" do
    entry = create(:feed_entry, raw_data: {
      "title" => "Video",
      "link" => "https://www.youtube.com/watch?v=abc123",
      "thumbnail" => "https://i.ytimg.com/vi/abc123/hqdefault.jpg"
    })

    normalizer = Normalizer::YoutubeNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal ["https://i.ytimg.com/vi/abc123/hqdefault.jpg"], post.attachment_urls
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
end
