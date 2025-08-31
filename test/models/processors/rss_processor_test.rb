require "test_helper"

class Processors::RssProcessorTest < ActiveSupport::TestCase
  test "should inherit from base processor" do
    feed = create(:feed, processor: "rss")
    processor = Processors::RssProcessor.new(feed, "test data")
    assert_kind_of Processors::Base, processor
  end

  test "should initialize without errors" do
    feed = create(:feed, processor: "rss")
    data = "test data"
    assert_nothing_raised do
      Processors::RssProcessor.new(feed, data)
    end
  end

  test "should respond to process method" do
    feed = create(:feed, processor: "rss")
    processor = Processors::RssProcessor.new(feed, "test data")
    assert_respond_to processor, :process
  end

  test "should process sample data" do
    feed = create(:feed, processor: "rss")
    processor = Processors::RssProcessor.new(feed, "sample xml data")
    
    result = processor.process
    
    assert_equal 2, result.length
    assert_equal "Sample Article", result[0][:title]
    assert_equal "Sample content", result[0][:content]
    assert_equal "Another Article", result[1][:title]
    assert_equal "More content", result[1][:content]
  end
end
