require "test_helper"
require "view_component/test_case"

class PostsHeatmapComponentTest < ViewComponent::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  test "#render should render nothing when user has no posts" do
    result = render_inline(PostsHeatmapComponent.new(user: user))
    assert_empty result.css(".heatmap-container")
  end

  test "#render should render heatmap when user has posts" do
    feed_entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: feed_entry)

    result = render_inline(PostsHeatmapComponent.new(user: user))

    assert result.css(".heatmap-container").any?
    assert_includes result.to_html, "Activity"
  end

  test "#render should generate SVG heatmap" do
    feed_entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: feed_entry)

    result = render_inline(PostsHeatmapComponent.new(user: user))

    # Check that SVG is present
    assert_includes result.to_html, "<svg"
    assert_includes result.to_html, "</svg>"
  end

  test "#render should use caching mechanism" do
    feed_entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: feed_entry)

    # Enable caching for this test
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    # First render should generate and cache
    component = PostsHeatmapComponent.new(user: user)
    first_result = render_inline(component)
    assert_includes first_result.to_html, "<svg"

    # Check cache was written
    cache_key = "user:#{user.id}:heatmap_svg:#{Date.current}"
    cached_svg = Rails.cache.read(cache_key)
    assert_not_nil cached_svg, "Cache should contain SVG after first render"
    assert_includes cached_svg, "<svg"

    # Second render should use cache (same content)
    cached_result = render_inline(PostsHeatmapComponent.new(user: user))
    assert_includes cached_result.to_html, "<svg"
  end
end
