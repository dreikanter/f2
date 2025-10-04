require "test_helper"

class Normalizer::XkcdNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/xkcd"
  end

  def processor_class
    Processor::RssProcessor
  end

  test "sholuld match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::XkcdNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end
end
