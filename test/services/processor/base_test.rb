require "test_helper"

class Processor::BaseTest < ActiveSupport::TestCase
  test "#process should raise NotImplementedError" do
    feed = create(:feed)
    processor = Processor::Base.new(feed, "test data")

    assert_raises(NotImplementedError) do
      processor.process
    end
  end
end
