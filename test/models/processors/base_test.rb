require "test_helper"

# Ensure all processor classes are loaded
require_relative "../../../app/models/processors/rss_processor"

class Processors::BaseTest < ActiveSupport::TestCase
  test "should initialize without errors" do
    feed = create(:feed)
    data = "test data"

    assert_nothing_raised do
      Processors::Base.new(feed, data)
    end
  end

  test "should raise NotImplementedError for process method" do
    feed = create(:feed)
    processor = Processors::Base.new(feed, "test data")

    assert_raises(NotImplementedError) do
      processor.process
    end
  end
end
