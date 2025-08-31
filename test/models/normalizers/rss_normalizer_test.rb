require "test_helper"

class Normalizers::RssNormalizerTest < ActiveSupport::TestCase
  test "should inherit from base normalizer" do
    feed = create(:feed, normalizer: "rss")
    normalizer = Normalizers::RssNormalizer.new(feed, [])
    assert_kind_of Normalizers::Base, normalizer
  end

  test "should initialize with feed and items" do
    feed = create(:feed, normalizer: "rss")
    items = ["item1", "item2"]
    normalizer = Normalizers::RssNormalizer.new(feed, items)
    assert_equal feed, normalizer.instance_variable_get(:@feed)
    assert_equal items, normalizer.instance_variable_get(:@processed_items)
  end

  test "should respond to normalize method" do
    feed = create(:feed, normalizer: "rss")
    normalizer = Normalizers::RssNormalizer.new(feed, [])
    assert_respond_to normalizer, :normalize
  end
end
