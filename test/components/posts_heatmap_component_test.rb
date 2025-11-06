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

  test "#render should cache heatmap SVG" do
    feed_entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: feed_entry)

    # First render should generate and cache
    component = PostsHeatmapComponent.new(user: user)
    render_inline(component)

    # Check cache was written
    cache_key = "user:#{user.id}:heatmap_svg:#{Date.current}"
    assert Rails.cache.exist?(cache_key)

    # Second render should use cache
    cached_result = render_inline(PostsHeatmapComponent.new(user: user))
    assert_includes cached_result.to_html, "<svg"
  end
end
