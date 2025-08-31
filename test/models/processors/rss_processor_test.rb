require "test_helper"

class Processors::RssProcessorTest < ActiveSupport::TestCase
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
