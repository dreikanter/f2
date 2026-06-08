require "test_helper"
require "view_component/test_case"

class FeedRefreshDescriptionComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, name: "Test Feed")
  end

  def refresh_event
    @refresh_event ||= Event.create!(type: "feed_refresh", level: :info, subject: feed, user: user, message: "", metadata: {})
  end

  test "#call should append the imported posts count" do
    create(:event_reference, event: refresh_event, reference: create(:post, feed: feed))
    create(:event_reference, event: refresh_event, reference: create(:post, feed: feed))

    result = render_inline(FeedRefreshDescriptionComponent.new(event: refresh_event))

    assert_includes result.to_html, "refreshed"
    assert_equal "(+2 posts)", result.css("[data-key='events.posts_count']").first&.text
  end

  test "#call should count only post references" do
    create(:event_reference, event: refresh_event, reference: create(:post, feed: feed))
    create(:event_reference, event: refresh_event, reference: user)

    result = render_inline(FeedRefreshDescriptionComponent.new(event: refresh_event))

    assert_equal "(+1 post)", result.css("[data-key='events.posts_count']").first&.text
  end

  test "#call should omit the count when the refresh imported nothing" do
    result = render_inline(FeedRefreshDescriptionComponent.new(event: refresh_event))

    assert_includes result.to_html, "refreshed"
    assert_nil result.css("[data-key='events.posts_count']").first
  end
end
