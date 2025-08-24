require "test_helper"

# Ensure all normalizer classes are loaded
require_relative "../../../app/models/normalizers/rss_normalizer"

class Normalizers::BaseTest < ActiveSupport::TestCase
  test "should raise NotImplementedError for normalize method" do
    feed = create(:feed)
    normalizer = Normalizers::Base.new(feed, [])

    assert_raises(NotImplementedError) do
      normalizer.normalize
    end
  end
end
