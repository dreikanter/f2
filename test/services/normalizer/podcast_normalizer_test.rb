require "test_helper"

class Normalizer::PodcastNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/podcast"
  end

  def processor_class
    Processor::PodcastProcessor
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    post = Normalizer::PodcastNormalizer.new(entry).normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should include the audio link in content" do
    entry = feed_entry(0)

    post = Normalizer::PodcastNormalizer.new(entry).normalize

    assert_includes post.content, "Listen: https://cdn.example.fm/signalpath/ep42.mp3"
  end

  test "#normalize should use the episode page as source_url" do
    entry = feed_entry(0)

    post = Normalizer::PodcastNormalizer.new(entry).normalize

    assert_equal "https://signalpath.example.fm/episodes/42", post.source_url
  end

  test "#normalize should use itunes_image as attachment" do
    entry = feed_entry(0)

    post = Normalizer::PodcastNormalizer.new(entry).normalize

    assert_equal ["https://signalpath.example.fm/art/ep42.jpg"], post.attachment_urls
  end

  test "#normalize should include stripped show notes as comment" do
    entry = feed_entry(0)

    post = Normalizer::PodcastNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "What keeps a power grid stable"
    assert_not_includes post.comments.first, "<a href"
  end

  test "#normalize should fall back to the enclosure URL when the episode has no page link" do
    entry = feed_entry(2)

    post = Normalizer::PodcastNormalizer.new(entry).normalize

    assert_equal "https://cdn.example.fm/signalpath/ep40.mp3", post.source_url
    assert_empty post.validation_errors
    assert_not_includes post.content, "Listen:"
  end
end
