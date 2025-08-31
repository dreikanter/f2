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
end
