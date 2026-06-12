require "test_helper"
require "view_component/test_case"

class PostsHeatmapComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  def metric_with_posts
    @metric_with_posts ||= create(:feed_metric, :with_posts, feed: feed, date: Date.current)
  end

  test "#render? should return false when there are no metrics" do
    component = PostsHeatmapComponent.new(feed: feed)
    render_inline(component)
    assert_not component.render?
  end

  test "#render? should return false when all metrics are outside the 1-year window" do
    create(:feed_metric, :with_posts, feed: feed, date: 2.years.ago.to_date)
    component = PostsHeatmapComponent.new(feed: feed)
    render_inline(component)
    assert_not component.render?
  end

  test "#render? should return true when there are metrics within the past year" do
    metric_with_posts
    component = PostsHeatmapComponent.new(feed: feed)
    render_inline(component)
    assert component.render?
  end

  test "#call should render an SVG for a feed with metrics" do
    metric_with_posts
    result = render_inline(PostsHeatmapComponent.new(feed: feed))
    assert result.css("svg").any?
  end

  test "#call should render an SVG for a user with metrics across feeds" do
    create(:feed_metric, :with_posts, feed: feed, date: Date.current)
    result = render_inline(PostsHeatmapComponent.new(user: user))
    assert result.css("svg").any?
  end

  test "#call should include data-tippy-content attributes on cells" do
    metric_with_posts
    result = render_inline(PostsHeatmapComponent.new(feed: feed))
    assert result.css("[data-tippy-content]").any?
  end

  test "#call should include data-controller attribute for Stimulus" do
    metric_with_posts
    result = render_inline(PostsHeatmapComponent.new(feed: feed))
    assert result.css("[data-controller='heatmap']").any?
  end

  test "#call should aggregate posts_count across all feeds for a user" do
    other_feed = create(:feed, user: user)
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 3)
    create(:feed_metric, feed: other_feed, date: Date.current, posts_count: 4)

    result = render_inline(PostsHeatmapComponent.new(user: user))
    assert result.css("svg").any?

    today_cell = result.css("[data-tippy-content='7']").first
    assert_not_nil today_cell
  end
end
