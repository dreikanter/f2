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
    assert_not_nil result.at_css('[data-key="feed.refreshing"][data-polling-target="content"]')
    assert_empty result.css('[role="alert"]')
  end

  test "#render should reserve the same spinner space while idle and refreshing" do
    [false, true].each do |requested|
      status = Feed::RefreshStatus.new(feed: feed, requested: requested)
      result = render_inline(FeedRefreshStatusComponent.new(status: status))
      classes = result.at_css('[data-key="feed.refresh-status"]')["class"].split

      assert_includes classes, "size-8"
      assert_includes classes, "shrink-0"
    end
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
