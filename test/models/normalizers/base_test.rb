require "test_helper"

# Ensure all normalizer classes are loaded
require_relative "../../../app/models/normalizers/rss_normalizer"

class Normalizers::BaseTest < ActiveSupport::TestCase
  test "should initialize with feed and items" do
    feed = create(:feed)
    items = ["item1", "item2"]
    normalizer = Normalizers::Base.new(feed, items)
    assert_equal feed, normalizer.instance_variable_get(:@feed)
    assert_equal items, normalizer.instance_variable_get(:@processed_items)
  end

  test "should raise NotImplementedError for normalize method" do
    feed = create(:feed)
    normalizer = Normalizers::Base.new(feed, [])

    assert_raises(NotImplementedError) do
      normalizer.normalize
    end
  end
end
