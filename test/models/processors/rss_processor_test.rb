require "test_helper"

class Processors::RssProcessorTest < ActiveSupport::TestCase
  test "should process sample data" do
    feed = create(:feed, processor: "rss")
    processor = Processors::RssProcessor.new(feed, "sample xml data")
    result = processor.process

    assert result.is_a?(Array)
 end
end
