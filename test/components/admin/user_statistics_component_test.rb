require "test_helper"
require "view_component/test_case"

class Admin::UserStatisticsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def stats
    @stats ||= UserStats.new(user)
  end

  def render_component
    render_inline(Admin::UserStatisticsComponent.new(stats: stats))
  end

  test "#call should render the stat rows with keys" do
    result = render_component

    assert_not_nil result.css('[data-key="stats.feeds"]').first
    assert_not_nil result.css('[data-key="stats.access_tokens"]').first
    assert_includes result.text, "Posts"
    assert_includes result.text, "Most Recent Post"
  end

  test "#call should summarize feed counts with a breakdown" do
    create(:feed, :enabled, user: user)
    result = render_component

    feeds = result.css('[data-key="stats.feeds.value"]').first
    assert_not_nil feeds
    assert_includes feeds.text, "total"
    assert_includes feeds.text, "enabled"
  end

  test "#call should show No posts yet when there are none" do
    result = render_component

    assert_includes result.text, "No posts yet"
  end
end
