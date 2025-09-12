require "test_helper"

class Loader::BaseTest < ActiveSupport::TestCase
  test "should initialize without errors" do
    feed = create(:feed)

    assert_nothing_raised do
      Loader::Base.new(feed)
    end
  end

  test "should initialize with options" do
    feed = create(:feed)
    options = { key: "value" }

    assert_nothing_raised do
      Loader::Base.new(feed, options)
    end
  end

  test "should raise NotImplementedError for load method" do
    feed = create(:feed)
    loader = Loader::Base.new(feed)

    assert_raises(NotImplementedError) do
      loader.load
    end
  end
end
