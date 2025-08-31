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

  test "should load sample data" do
    feed = create(:feed, loader: "http")
    loader = Loaders::HttpLoader.new(feed)

    result = loader.load

    assert_equal :success, result[:status]
    assert_equal "sample feed content", result[:data]
    assert_equal "application/xml", result[:content_type]
  end
end
