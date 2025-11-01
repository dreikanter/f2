require "test_helper"

class Loader::BaseTest < ActiveSupport::TestCase
  test "#initialize should run without errors" do
    feed = create(:feed)

    assert_nothing_raised do
      Loader::Base.new(feed)
    end
  end

  test "#initialize should accept options hash" do
    feed = create(:feed)
    options = { key: "value" }

    assert_nothing_raised do
      Loader::Base.new(feed, options)
    end
  end

  test "#load should raise NotImplementedError" do
    feed = create(:feed)
    loader = Loader::Base.new(feed)

    assert_raises(NotImplementedError) do
      loader.load
    end
  end
end
