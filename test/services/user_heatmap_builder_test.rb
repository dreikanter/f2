require "test_helper"

class UserHeatmapBuilderTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  test "#build should generate SVG when user has metrics" do
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 5)

    builder = UserHeatmapBuilder.new(user)
    svg = builder.build
    doc = Nokogiri::XML(svg)

    assert_empty doc.errors, "SVG should be well-formed XML"
    assert_equal 1, doc.css("svg").size, "Should have exactly one <svg> element"
  end

  test "#build should handle empty data" do
    builder = UserHeatmapBuilder.new(user)
    svg = builder.build
    doc = Nokogiri::XML(svg)

    assert_empty doc.errors, "SVG should be well-formed XML"
    assert_equal 1, doc.css("svg").size, "Should have exactly one <svg> element"
  end

  test "#build_cached should cache the result" do
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 5)

    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    builder = UserHeatmapBuilder.new(user)
    first_svg = builder.build_cached
    second_svg = nil

    assert_no_queries do
      second_svg = builder.build_cached
    end

    assert_equal first_svg, second_svg
  end

  test "#build_cached should accept custom expiration time" do
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 5)

    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    ttl = 1.hour
    builder = UserHeatmapBuilder.new(user)
    builder.build_cached(expires_in: ttl)

    cache_key = "user:#{user.id}:heatmap_svg:#{Date.current}"
    assert_not_nil Rails.cache.read(cache_key), "Cache should exist initially"

    travel_to (ttl + 1.second).from_now do
      cached_svg = Rails.cache.read(cache_key)
      assert_nil cached_svg, "Cache should expire"
    end
  end
end
