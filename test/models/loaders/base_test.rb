require "test_helper"

# Ensure all loader classes are loaded
require_relative "../../../app/models/loaders/http_loader"

class Loaders::BaseTest < ActiveSupport::TestCase
  test "should initialize without errors" do
    feed = create(:feed)

    assert_nothing_raised do
      Loaders::Base.new(feed)
    end
  end

  test "should raise NotImplementedError for load method" do
    feed = create(:feed)
    loader = Loaders::Base.new(feed)

    assert_raises(NotImplementedError) do
      loader.load
    end
  end
end
