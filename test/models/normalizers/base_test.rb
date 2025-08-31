require "test_helper"

# Ensure all normalizer classes are loaded
require_relative "../../../app/models/normalizers/rss_normalizer"

class Normalizers::BaseTest < ActiveSupport::TestCase
  test "should initialize without errors" do
    feed = create(:feed)
    items = ["item1", "item2"]
    assert_nothing_raised do
      Normalizers::Base.new(feed, items)
    end
  end

  test "should raise NotImplementedError for normalize method" do
    feed = create(:feed)
    normalizer = Normalizers::Base.new(feed, [])

    assert_raises(NotImplementedError) do
      normalizer.normalize
    end
  end
end
