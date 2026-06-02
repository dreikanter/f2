require "test_helper"
require "view_component/test_case"

class FeedFilterDropdownComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feeds
    @feeds ||= [
      create(:feed, user: user, name: "Alpha"),
      create(:feed, user: user, name: "Beta")
    ]
  end

  test "#render should show All feeds option" do
    result = render_inline FeedFilterDropdownComponent.new(
      feeds: feeds,
      selected_feed: nil,
      sort_params: {},
      menu_id: "test-menu"
    )

    assert_includes result.text, "All feeds"
    assert_not_empty result.css("[data-key='feed-filter.button']")
  end

  test "#render should show All feeds as button label when no feed selected" do
    result = render_inline FeedFilterDropdownComponent.new(
      feeds: feeds,
      selected_feed: nil,
      sort_params: {},
      menu_id: "test-menu"
    )

    button = result.css("[data-key='feed-filter.button']").first
    assert_includes button.text, "All feeds"
  end

  test "#render should show selected feed name in button label" do
    result = render_inline FeedFilterDropdownComponent.new(
      feeds: feeds,
      selected_feed: feeds.first,
      sort_params: {},
      menu_id: "test-menu"
    )

    button = result.css("[data-key='feed-filter.button']").first
    assert_includes button.text, "Alpha"
  end

  test "#render should list all feeds" do
    result = render_inline FeedFilterDropdownComponent.new(
      feeds: feeds,
      selected_feed: nil,
      sort_params: {},
      menu_id: "test-menu"
    )

    assert_includes result.text, "Alpha"
    assert_includes result.text, "Beta"
  end

  test "#render should include search input" do
    result = render_inline FeedFilterDropdownComponent.new(
      feeds: feeds,
      selected_feed: nil,
      sort_params: {},
      menu_id: "test-menu"
    )

    assert_not_empty result.css("input[data-feed-filter-target='search']")
  end

  test "#render should preserve sort params in feed links" do
    result = render_inline FeedFilterDropdownComponent.new(
      feeds: feeds,
      selected_feed: nil,
      sort_params: { sort: "feed", direction: "asc" },
      menu_id: "test-menu"
    )

    links = result.css("a[href*='feed_id']")
    assert links.all? { |link| link["href"].include?("sort=feed") }
    assert links.all? { |link| link["href"].include?("direction=asc") }
  end
end
