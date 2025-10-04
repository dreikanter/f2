require "test_helper"

class Normalizer::XkcdNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "normalizers/xkcd"
  end

  def processor_class
    Processor::RssProcessor
  end

  test "sholuld match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::XkcdNormalizer.new(entry)
    post = normalizer.normalize

    snapshot = JSON.pretty_generate(serialize_post(post))
    assert_matches_snapshot(snapshot, snapshot: "#{fixture_dir}/normalized.json")
  end
end
