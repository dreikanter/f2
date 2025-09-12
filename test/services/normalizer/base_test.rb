require "test_helper"

class Normalizer::BaseTest < ActiveSupport::TestCase
  test "should initialize without errors" do
    feed = create(:feed)
    items = ["item1", "item2"]

    assert_nothing_raised do
      Normalizer::Base.new(feed, items)
    end
  end

  test "should raise NotImplementedError for normalize method" do
    feed = create(:feed)
    normalizer = Normalizer::Base.new(feed, [])

    assert_raises(NotImplementedError) do
      normalizer.normalize
    end
  end
end
