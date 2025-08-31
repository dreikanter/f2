require "test_helper"

class Processors::RssProcessorTest < ActiveSupport::TestCase
  test "should inherit from base processor" do
    feed = create(:feed, processor: "rss")
    processor = Processors::RssProcessor.new(feed, "test data")
    assert_kind_of Processors::Base, processor
  end

  test "should initialize with feed and data" do
    feed = create(:feed, processor: "rss")
    data = "test data"
    processor = Processors::RssProcessor.new(feed, data)
    assert_equal feed, processor.instance_variable_get(:@feed)
    assert_equal data, processor.instance_variable_get(:@raw_data)
  end

  test "should respond to process method" do
    feed = create(:feed, processor: "rss")
    processor = Processors::RssProcessor.new(feed, "test data")
    assert_respond_to processor, :process
  end
end
