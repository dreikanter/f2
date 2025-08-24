require "test_helper"

# Ensure all loader classes are loaded
require_relative "../../../app/models/loaders/http_loader"

class Loaders::BaseTest < ActiveSupport::TestCase
  test "should raise NotImplementedError for load method" do
    feed = create(:feed)
    loader = Loaders::Base.new(feed)

    assert_raises(NotImplementedError) do
      loader.load
    end
  end

  test "should track descendants" do
    # HttpLoader should be a descendant
    assert_includes Loaders::Base.descendants, Loaders::HttpLoader
  end

  test "should provide available loaders list" do
    loaders = Loaders::Base.available_loaders
    assert_includes loaders, "Http"
    assert loaders.all? { |loader| loader.is_a?(String) }
  end
end
