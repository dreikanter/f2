require "test_helper"

# Ensure all processor classes are loaded
require_relative "../../../app/models/processors/rss_processor"
require_relative "../../../app/models/processors/json_processor"

class Processors::BaseTest < ActiveSupport::TestCase
  test "should raise NotImplementedError for process method" do
    feed = create(:feed)
    processor = Processors::Base.new(feed, "test data")

    assert_raises(NotImplementedError) do
      processor.process
    end
  end

  test "should track descendants" do
    assert_includes Processors::Base.descendants, Processors::RssProcessor
    assert_includes Processors::Base.descendants, Processors::JsonProcessor
  end

  test "should provide available processors list" do
    processors = Processors::Base.available_processors
    assert_includes processors, "Json"
    assert_includes processors, "Rss"
    assert processors.all? { |processor| processor.is_a?(String) }
  end
end
