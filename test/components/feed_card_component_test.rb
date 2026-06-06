require "test_helper"
require "view_component/test_case"

class FeedCardComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, :disabled, user: user, name: "My Feed")
  end

  test "#render should use dom_id as element id" do
    result = render_inline FeedCardComponent.new(feed: feed)

    assert_not_empty result.css("##{ActionView::RecordIdentifier.dom_id(feed)}")
  end

  test "#render should link title to feed detail page" do
    result = render_inline FeedCardComponent.new(feed: feed)

    link = result.at_css("a[href*='/feeds/']")
    assert_not_nil link
    assert_includes link.text, "My Feed"
  end

  test "#render should show Draft badge for draft feeds" do
    draft_feed = create(:feed, :draft, user: user)
    result = render_inline FeedCardComponent.new(feed: draft_feed)

    badge = result.css("[data-key='feed.#{draft_feed.id}.draft_badge']").first
    assert_not_nil badge
    assert_equal "Draft", badge.text.strip
  end

  test "#render should show Disabled badge for disabled feeds" do
    result = render_inline FeedCardComponent.new(feed: feed)

    badge = result.css("[data-key='feed.#{feed.id}.disabled_badge']").first
    assert_not_nil badge
    assert_equal "Disabled", badge.text.strip
  end

  test "#render should show Active badge for enabled feeds" do
    enabled_feed = create(:feed, :enabled, user: user)
    result = render_inline FeedCardComponent.new(feed: enabled_feed)

    badge = result.css("[data-key='feed.#{enabled_feed.id}.enabled_badge']").first
    assert_not_nil badge
    assert_equal "Active", badge.text.strip
  end

  test "#render should show @group label when target_group present" do
    result = render_inline FeedCardComponent.new(feed: feed)

    assert_includes result.text, "@testgroup"
  end

  test "#render should show Continue setup and Discard in dropdown for draft feeds" do
    draft_feed = create(:feed, :draft, user: user)

    with_request_url("/feeds") do
      result = render_inline FeedCardComponent.new(feed: draft_feed)

      assert_not_empty result.css("[data-key='feed.#{draft_feed.id}.continue_setup']")
      assert_not_empty result.css("[data-key='feed.#{draft_feed.id}.discard']")
    end
  end

  test "#render should not show draft actions for non-draft feeds" do
    with_request_url("/feeds") do
      result = render_inline FeedCardComponent.new(feed: feed)

      assert_empty result.css("[data-key='feed.#{feed.id}.continue_setup']")
      assert_empty result.css("[data-key='feed.#{feed.id}.discard']")
    end
  end

  test "#render should show refresh and post time placeholders when never refreshed" do
    result = render_inline FeedCardComponent.new(feed: feed)

    assert_includes result.text, "Never"
    assert_includes result.text, "None"
  end

  test "#render should label the activity times" do
    result = render_inline FeedCardComponent.new(feed: feed)

    assert_includes result.text, "Updated:"
    assert_includes result.text, "Post:"
  end
end
