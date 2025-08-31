require "test_helper"

class Loaders::HttpLoaderTest < ActiveSupport::TestCase
  test "should inherit from base loader" do
    feed = create(:feed, loader: "http")
    loader = Loaders::HttpLoader.new(feed)
    assert_kind_of Loaders::Base, loader
  end

  test "should initialize without errors" do
    feed = create(:feed, loader: "http")
    assert_nothing_raised do
      Loaders::HttpLoader.new(feed)
    end
  end

  test "should respond to load method" do
    feed = create(:feed, loader: "http")
    loader = Loaders::HttpLoader.new(feed)
    assert_respond_to loader, :load
  end
end
