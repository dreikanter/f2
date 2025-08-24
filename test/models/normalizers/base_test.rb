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

  test "should track descendants" do
    assert_includes Normalizers::Base.descendants, Normalizers::RssNormalizer
  end

  test "should provide available normalizers list" do
    normalizers = Normalizers::Base.available_normalizers
    assert_includes normalizers, "Rss"
    assert normalizers.all? { |normalizer| normalizer.is_a?(String) }
  end
end
