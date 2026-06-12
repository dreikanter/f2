require "test_helper"

class Normalizer::LobstersNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/lobsters"
  end

  def processor_class
    Processor::RssProcessor
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::LobstersNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should link the discussion page with tags in a comment" do
    entry = feed_entry(0)

    post = Normalizer::LobstersNormalizer.new(entry).normalize

    assert_equal ["Comments: https://lobste.rs/s/aaaaaa #sample #testing"], post.comments
  end

  test "#normalize should use the external story URL as source_url" do
    entry = feed_entry(0)

    post = Normalizer::LobstersNormalizer.new(entry).normalize

    assert_equal "https://example.com/first-sample-story", post.source_url
  end
end
