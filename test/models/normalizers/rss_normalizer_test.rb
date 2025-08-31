require "test_helper"

class Normalizers::RssNormalizerTest < ActiveSupport::TestCase
  test "should inherit from base normalizer" do
    feed = create(:feed, normalizer: "rss")
    normalizer = Normalizers::RssNormalizer.new(feed, [])
    assert_kind_of Normalizers::Base, normalizer
  end

  test "should initialize without errors" do
    feed = create(:feed, normalizer: "rss")
    items = ["item1", "item2"]
    assert_nothing_raised do
      Normalizers::RssNormalizer.new(feed, items)
    end
  end

  test "should respond to normalize method" do
    feed = create(:feed, normalizer: "rss")
    normalizer = Normalizers::RssNormalizer.new(feed, [])
    assert_respond_to normalizer, :normalize
  end
end
