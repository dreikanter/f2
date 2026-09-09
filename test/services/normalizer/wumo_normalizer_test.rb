require "test_helper"

class Normalizer::WumoNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/wumo"
  end

  def processor_class
    Processor::WumoProcessor
  end

  test "#normalize should preserve feeder's title link image and date" do
    post = Normalizer::WumoNormalizer.new(feed_entry(0)).normalize

    assert_equal "Wumo 28. Jul 2023 - http://wumo.com/wumo/2023/07/28", post.content
    assert_equal ["http://wumo.com/img/wumo/2023/07/wumo64abf9be2497a4.68979190.jpg"], post.attachment_urls
    assert_equal Time.utc(2023, 7, 28), post.published_at
    assert_empty post.comments
    assert post.enqueued?
  end

  test "#normalize should reject entries with no comic" do
    post = Normalizer::WumoNormalizer.new(feed_entry(1)).normalize

    assert post.rejected?
    assert_includes post.validation_errors, "missing_images"
  end

  test "#normalize should reject an entry with an unknown publication date" do
    entry = feed_entry(0)
    entry.published_at = nil

    post = Normalizer::WumoNormalizer.new(entry).normalize

    assert post.rejected?
    assert_includes post.validation_errors, "missing_publication_date"
  end
end
