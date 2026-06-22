require "test_helper"
require "view_component/test_case"

class FeedListItemComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, :disabled, user: user, name: "My Feed")
  end

  test "#render should use dom_id as element id" do
    result = render_inline FeedListItemComponent.new(feed: feed)

    assert_not_empty result.css("##{ActionView::RecordIdentifier.dom_id(feed)}")
  end

  test "#render should link title to feed detail page" do
    result = render_inline FeedListItemComponent.new(feed: feed)

    link = result.at_css("a[href*='/feeds/']")
    assert_not_nil link
    assert_includes link.text, "My Feed"
  end

  test "#render should show draft status icon for draft feeds" do
    draft_feed = create(:feed, :draft, user: user)
    result = render_inline FeedListItemComponent.new(feed: draft_feed)

    icon = result.at_css("[data-key='feed.#{draft_feed.id}.status_icon'] svg")
    assert_not_nil icon
    assert_equal "Draft", icon["aria-label"]
  end

  test "#render should show disabled status icon for disabled feeds" do
    result = render_inline FeedListItemComponent.new(feed: feed)

    icon = result.at_css("[data-key='feed.#{feed.id}.status_icon'] svg")
    assert_not_nil icon
    assert_equal "Disabled", icon["aria-label"]
  end

  test "#render should show enabled status icon for enabled feeds" do
    enabled_feed = create(:feed, :enabled, user: user)
    result = render_inline FeedListItemComponent.new(feed: enabled_feed)

    icon = result.at_css("[data-key='feed.#{enabled_feed.id}.status_icon'] svg")
    assert_not_nil icon
    assert_equal "Enabled", icon["aria-label"]
  end

  test "#render should show @group label when target_group present" do
    result = render_inline FeedListItemComponent.new(feed: feed)

    assert_includes result.text, "@testgroup"
  end

  test "#render should show Continue setup and Discard in dropdown for draft feeds" do
    draft_feed = create(:feed, :draft, user: user)

    with_request_url("/feeds") do
      result = render_inline FeedListItemComponent.new(feed: draft_feed)

      assert_not_empty result.css("[data-key='feed.#{draft_feed.id}.continue_setup']")
      assert_not_empty result.css("[data-key='feed.#{draft_feed.id}.discard']")
    end
  end

  test "#render should not show draft actions for non-draft feeds" do
    with_request_url("/feeds") do
      result = render_inline FeedListItemComponent.new(feed: feed)

      assert_empty result.css("[data-key='feed.#{feed.id}.continue_setup']")
      assert_empty result.css("[data-key='feed.#{feed.id}.discard']")
    end
  end

  test "#render should show Details action for every feed" do
    with_request_url("/feeds") do
      result = render_inline FeedListItemComponent.new(feed: feed)

      details = result.css("[data-key='feed.#{feed.id}.details']").first
      assert_not_nil details
      assert_equal "Details", details.text.strip
      assert_includes details["href"], "/feeds/#{feed.id}"
    end
  end

  test "#render should show Source action opening the feed source in a new tab" do
    with_request_url("/feeds") do
      result = render_inline FeedListItemComponent.new(feed: feed)

      source = result.css("[data-key='feed.#{feed.id}.source']").first
      assert_not_nil source
      assert_equal "Source", source.text.strip
      assert_equal "https://example.com/feed.xml", source["href"]
      assert_equal "_blank", source["target"]
    end
  end

  test "#render should not show Source for query-shaped feeds" do
    query_feed = create(:feed, user: user, feed_profile_key: "llm_web_search",
      params: { "query" => "ruby news" })

    with_request_url("/feeds") do
      result = render_inline FeedListItemComponent.new(feed: query_feed)

      assert_empty result.css("[data-key='feed.#{query_feed.id}.source']")
    end
  end

  test "#render should show Edit action for non-draft feeds" do
    with_request_url("/feeds") do
      result = render_inline FeedListItemComponent.new(feed: feed)

      edit = result.css("[data-key='feed.#{feed.id}.edit']").first
      assert_not_nil edit
      assert_includes edit["href"], "/feeds/#{feed.id}/edit"
    end
  end

  test "#render should show Enable action for enableable disabled feeds" do
    with_request_url("/feeds") do
      result = render_inline FeedListItemComponent.new(feed: feed)

      assert_not_empty result.css("[data-key='feed.#{feed.id}.enable']")
      assert_empty result.css("[data-key='feed.#{feed.id}.disable']")
    end
  end

  test "#render should show Disable action for enabled feeds" do
    enabled_feed = create(:feed, :enabled, user: user)

    with_request_url("/feeds") do
      result = render_inline FeedListItemComponent.new(feed: enabled_feed)

      assert_not_empty result.css("[data-key='feed.#{enabled_feed.id}.disable']")
      assert_empty result.css("[data-key='feed.#{enabled_feed.id}.enable']")
    end
  end

  test "#render should not show status toggle for draft feeds" do
    draft_feed = create(:feed, :draft, user: user)

    with_request_url("/feeds") do
      result = render_inline FeedListItemComponent.new(feed: draft_feed)

      assert_empty result.css("[data-key='feed.#{draft_feed.id}.enable']")
      assert_empty result.css("[data-key='feed.#{draft_feed.id}.disable']")
      assert_empty result.css("[data-key='feed.#{draft_feed.id}.edit']")
    end
  end

  test "#render should show refresh and post time placeholders when never refreshed" do
    result = render_inline FeedListItemComponent.new(feed: feed)

    assert_includes result.text, "Never"
    assert_includes result.text, "None"
  end

  test "#render should label the activity times" do
    result = render_inline FeedListItemComponent.new(feed: feed)

    assert_includes result.text, "Latest updated:"
    assert_includes result.text, "Latest post:"
  end

  test "#render should show plain text status for disabled feeds" do
    result = render_inline FeedListItemComponent.new(feed: feed)

    status = result.at_css("[data-key='feed.#{feed.id}.status']")
    assert_not_nil status
    assert_equal "Disabled", status.text.strip
  end

  test "#render should show plain text status for enabled feeds" do
    enabled_feed = create(:feed, :enabled, user: user)
    result = render_inline FeedListItemComponent.new(feed: enabled_feed)

    status = result.at_css("[data-key='feed.#{enabled_feed.id}.status']")
    assert_not_nil status
    assert_equal "Enabled", status.text.strip
  end

  test "#render should show plain text status for draft feeds" do
    draft_feed = create(:feed, :draft, user: user)
    result = render_inline FeedListItemComponent.new(feed: draft_feed)

    status = result.at_css("[data-key='feed.#{draft_feed.id}.status']")
    assert_not_nil status
    assert_equal "Draft", status.text.strip
  end

  test "#render should not show activity times for draft feeds" do
    draft_feed = create(:feed, :draft, user: user)
    result = render_inline FeedListItemComponent.new(feed: draft_feed)

    assert_empty result.css("[data-key='feed.#{draft_feed.id}.last_refreshed']")
    assert_empty result.css("[data-key='feed.#{draft_feed.id}.most_recent_post']")
    assert_not_includes result.text, "Latest updated:"
    assert_not_includes result.text, "Latest post:"
  end

  test "#render should link title to admin feed page in admin mode" do
    result = render_inline FeedListItemComponent.new(feed: feed, admin: true)

    link = result.at_css("a[href*='/admin/feeds/']")
    assert_not_nil link
    assert_includes link.text, "My Feed"
  end

  test "#render should show owner in admin mode" do
    result = render_inline FeedListItemComponent.new(feed: feed, admin: true)

    owner = result.css("[data-key='feed.#{feed.id}.owner']").first
    assert_not_nil owner
    assert_includes owner.text, user.email_address
  end

  test "#render should not show owner outside admin mode" do
    result = render_inline FeedListItemComponent.new(feed: feed)

    assert_empty result.css("[data-key='feed.#{feed.id}.owner']")
  end

  test "#render should show published posts count for non-draft feeds" do
    feed_with_posts = create(:feed, :disabled, user: user, published_posts_count: 3)
    result = render_inline FeedListItemComponent.new(feed: feed_with_posts)

    posts_count = result.at_css("[data-key='feed.#{feed_with_posts.id}.published_posts_count']")
    assert_not_nil posts_count
    assert_includes posts_count.text, "Posts: 3"
  end

  test "#render should not show published posts count for draft feeds" do
    draft_feed = create(:feed, :draft, user: user)
    result = render_inline FeedListItemComponent.new(feed: draft_feed)

    assert_empty result.css("[data-key='feed.#{draft_feed.id}.published_posts_count']")
  end

  test "#render should not show management actions in admin mode" do
    enabled_feed = create(:feed, :enabled, user: user)

    with_request_url("/admin/feeds") do
      result = render_inline FeedListItemComponent.new(feed: enabled_feed, admin: true)

      assert_empty result.css("[data-key='feed.#{enabled_feed.id}.edit']")
      assert_empty result.css("[data-key='feed.#{enabled_feed.id}.disable']")
      assert_not_empty result.css("[data-key='feed.#{enabled_feed.id}.details']")
    end
  end
end
