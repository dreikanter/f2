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

    assert_includes svg, "<svg"
    assert_includes svg, "</svg>"
  end

  test "#build should handle empty data" do
    builder = UserHeatmapBuilder.new(user)
    svg = builder.build

    assert_includes svg, "<svg"
    assert_includes svg, "</svg>"
  end

  test "#build_cached should cache the SVG" do
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 5)

    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    builder = UserHeatmapBuilder.new(user)
    svg = builder.build_cached

    cache_key = "user:#{user.id}:heatmap_svg:#{Date.current}"
    cached_svg = Rails.cache.read(cache_key)

    assert_not_nil cached_svg
    assert_equal svg, cached_svg
    assert_includes cached_svg, "<svg"
  end

  test "#build_cached should use cached SVG on second call" do
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 5)

    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    builder = UserHeatmapBuilder.new(user)
    first_svg = builder.build_cached

    # Modify the cache to verify second call uses it
    cache_key = "user:#{user.id}:heatmap_svg:#{Date.current}"
    Rails.cache.write(cache_key, "cached_content", expires_in: 24.hours)

    second_svg = builder.build_cached

    assert_equal "cached_content", second_svg
    assert_not_equal first_svg, second_svg
  end

  test "#build_cached should expire cache after 24 hours" do
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 5)

    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    builder = UserHeatmapBuilder.new(user)
    builder.build_cached

    cache_key = "user:#{user.id}:heatmap_svg:#{Date.current}"
    assert_not_nil Rails.cache.read(cache_key), "Cache should exist initially"

    # Travel forward 25 hours
    travel 25.hours do
      cached_svg = Rails.cache.read(cache_key)
      assert_nil cached_svg, "Cache should expire after 24 hours"
    end
  end

  test "#build_cached should accept custom expiration time" do
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 5)

    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    builder = UserHeatmapBuilder.new(user)
    builder.build_cached(expires_in: 1.hour)

    cache_key = "user:#{user.id}:heatmap_svg:#{Date.current}"
    assert_not_nil Rails.cache.read(cache_key), "Cache should exist initially"

    # Travel forward 2 hours
    travel 2.hours do
      cached_svg = Rails.cache.read(cache_key)
      assert_nil cached_svg, "Cache should expire after 1 hour"
    end
  end
end
