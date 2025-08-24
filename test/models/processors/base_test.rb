require "test_helper"

# Ensure all processor classes are loaded
require_relative "../../../app/models/processors/rss_processor"

class Processors::BaseTest < ActiveSupport::TestCase
  test "should raise NotImplementedError for process method" do
    feed = create(:feed)
    processor = Processors::Base.new(feed, "test data")

    assert_raises(NotImplementedError) do
      processor.process
    end
  end
end
