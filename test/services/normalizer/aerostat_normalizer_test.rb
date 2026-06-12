require "test_helper"

class Normalizer::AerostatNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/aerostat"
  end

  def processor_class
    Processor::AerostatProcessor
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::AerostatNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should include enclosure URL in content" do
    entry = feed_entry(0)

    post = Normalizer::AerostatNormalizer.new(entry).normalize

    assert_includes post.content, "Запись: https://aerostats.getmobileup.com/music/1094.mp3"
  end

  test "#normalize should use itunes_image as attachment" do
    entry = feed_entry(0)

    post = Normalizer::AerostatNormalizer.new(entry).normalize

    assert_equal ["https://aerostatbg.ru/sites/default/files/styles/rss_image/public/releases/1094.jpg?itok=IpSaPXdB"], post.attachment_urls
  end

  test "#normalize should include stripped summary as comment" do
    entry = feed_entry(0)

    post = Normalizer::AerostatNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "Мне приходят письма"
  end
end
