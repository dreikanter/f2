require "test_helper"

class Normalizer::BaseTest < ActiveSupport::TestCase
  test "should initialize without errors" do
    feed_entry = create(:feed_entry)

    assert_nothing_raised do
      Normalizer::Base.new(feed_entry)
    end
  end
end
