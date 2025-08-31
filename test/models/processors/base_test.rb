require "test_helper"

# Ensure all processor classes are loaded
require_relative "../../../app/models/processors/rss_processor"

class Processors::BaseTest < ActiveSupport::TestCase
  test "should initialize with feed and data" do
    feed = create(:feed)
    data = "test data"
    processor = Processors::Base.new(feed, data)
    assert_equal feed, processor.instance_variable_get(:@feed)
    assert_equal data, processor.instance_variable_get(:@raw_data)
  end

  test "should raise NotImplementedError for process method" do
    feed = create(:feed)
    processor = Processors::Base.new(feed, "test data")

    assert_raises(NotImplementedError) do
      processor.process
    end
  end
end
