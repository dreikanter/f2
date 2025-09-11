require "test_helper"

class Loaders::HttpLoaderTest < ActiveSupport::TestCase
  test "should load sample data" do
    feed = create(:feed, loader: "http")
    loader = Loaders::HttpLoader.new(feed)

    result = loader.load

    assert_equal :success, result[:status]
    assert_equal "sample feed content", result[:data]
    assert_equal "application/xml", result[:content_type]
  end
end
