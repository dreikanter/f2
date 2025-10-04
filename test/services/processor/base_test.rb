require "test_helper"

class Processor::BaseTest < ActiveSupport::TestCase
  test "should raise NotImplementedError for process method" do
    feed = create(:feed)
    processor = Processor::Base.new(feed, "test data")

    assert_raises(NotImplementedError) do
      processor.process
    end
  end
end
