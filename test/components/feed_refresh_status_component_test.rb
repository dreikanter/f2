require "test_helper"
require "view_component/test_case"

class FeedRefreshStatusComponentTest < ViewComponent::TestCase
  def feed
    @feed ||= create(:feed)
  end

  test "#render should keep an empty status target before the first refresh" do
    result = render_inline(FeedRefreshStatusComponent.new(status: Feed::RefreshStatus.new(feed: feed)))

    assert_empty result.at_css('[data-key="feed.refresh-status"]').text.strip
    assert_empty result.css('[data-key="feed.refreshing"]')
  end

  test "#render should show an accessible spinner while refreshing" do
    status = Feed::RefreshStatus.new(feed: feed, requested: true)
    result = render_inline(FeedRefreshStatusComponent.new(status: status))

    assert_not_nil result.at_css('[data-key="feed.refresh-status"][role="status"]')
    assert_not_nil result.at_css('[data-key="feed.refreshing"] svg')
    assert_includes result.at_css('[data-key="feed.refreshing"]').text, "Refreshing feed"
  end

  test "#render should show the result after refreshing" do
    create(:event, subject: feed, type: "feed_refresh",
                   metadata: { status: "completed", stats: { new_posts: 2 } })
    result = render_inline(FeedRefreshStatusComponent.new(status: Feed::RefreshStatus.new(feed: feed)))

    assert_includes result.at_css('[data-key="feed.refresh-status"]').text, "2 new posts"
    assert_empty result.css('[data-key="feed.refreshing"]')
  end
end
