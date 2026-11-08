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
    assert_empty result.css('[data-controller="polling"]')
  end

  test "#render should show an accessible spinner while refreshing" do
    status = Feed::RefreshStatus.new(feed: feed, requested: true)
    result = render_inline(FeedRefreshStatusComponent.new(status: status))

    assert_not_nil result.at_css('[data-key="feed.refresh-status"][role="status"]')
    assert_not_nil result.at_css('[data-key="feed.refreshing"] svg')
    assert_includes result.at_css('[data-key="feed.refreshing"]').text, "Refreshing feed"
    polling = result.at_css('[data-key="feed.refresh-status"][data-controller="polling"]')
    assert_equal "60", polling["data-polling-max-polls-value"]
    assert_equal "5000", polling["data-polling-interval-value"]
    assert_includes polling["data-polling-endpoint-value"], "refresh_after=none"
    assert_not_nil result.at_css('[data-key="feed.refreshing"][data-polling-target="content"]')
    assert_not_nil result.at_css('[data-key="feed.refresh-notice"][data-polling-target="timeoutMessage"][hidden]')
  end

  %w[completed failed interrupted].each do |outcome|
    test "#render should keep an empty status target after a #{outcome} refresh" do
      create(:event, subject: feed, type: "feed_refresh",
                     metadata: { status: outcome, stats: { new_posts: 2 } })
      result = render_inline(FeedRefreshStatusComponent.new(status: Feed::RefreshStatus.new(feed: feed)))

      assert_empty result.at_css('[data-key="feed.refresh-status"]').text.strip
      assert_empty result.css('[data-key="feed.refreshing"]')
      assert_empty result.css('[data-controller="polling"]')
    end
  end
end
