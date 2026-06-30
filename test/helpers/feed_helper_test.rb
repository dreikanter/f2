require "test_helper"

class FeedHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "#feed_missing_enablement_parts should return both missing parts" do
    feed = build(:feed, :without_access_token)
    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token", "target group"], result
  end

  test "#feed_missing_enablement_parts should return missing access token only" do
    feed = build(:feed, :without_access_token, target_group: "test_group")
    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token"], result
  end

  test "#feed_missing_enablement_parts should return missing target group only" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: nil)
    result = feed_missing_enablement_parts(feed)

    assert_equal ["target group"], result
  end

  test "#feed_missing_enablement_parts should return missing access token when inactive" do
    access_token = create(:access_token, :inactive)
    feed = build(:feed, access_token: access_token, target_group: "test_group")
    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token"], result
  end

  test "#feed_missing_enablement_parts should return empty array when all requirements met" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: "test_group")
    result = feed_missing_enablement_parts(feed)

    assert_equal [], result
  end

  test "#feed_missing_enablement_parts should include name when blank" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: "test_group", name: "")
    result = feed_missing_enablement_parts(feed)

    assert_includes result, "name"
  end

  test "#feed_status_icon should render enabled icon" do
    feed = build(:feed, :enabled)

    result = feed_status_icon(feed)

    assert_includes result, "<svg"
    assert_includes result, "text-success"
    assert_includes result, 'title="Enabled"'
    assert_includes result, 'aria-label="Enabled"'
    assert_includes result, 'role="img"'
  end

  test "#feed_status_icon should render disabled icon" do
    feed = build(:feed, :disabled)

    result = feed_status_icon(feed)

    assert_includes result, "<svg"
    assert_includes result, "text-muted"
    assert_includes result, 'title="Disabled"'
    assert_includes result, 'aria-label="Disabled"'
    assert_includes result, 'role="img"'
  end

  test "#feed_status_icon should render draft icon" do
    feed = build(:feed, :draft)

    result = feed_status_icon(feed)

    assert_includes result, "<svg"
    assert_includes result, "text-muted"
    assert_includes result, 'title="Draft"'
    assert_includes result, 'aria-label="Draft"'
    assert_includes result, 'role="img"'
  end

  test "#feed_summary_line should describe active, inactive, and draft counts" do
    result = feed_summary_line(active_count: 2, inactive_count: 1, draft_count: 3)
    assert_equal "You have 2 active feeds, 1 inactive feed, and 3 draft feeds", result
  end

  test "#feed_summary_line should describe active and inactive counts" do
    result = feed_summary_line(active_count: 2, inactive_count: 1, draft_count: 0)
    assert_equal "You have 2 active feeds and 1 inactive feed", result
  end

  test "#feed_summary_line should handle single active count" do
    result = feed_summary_line(active_count: 1, inactive_count: 0, draft_count: 0)
    assert_equal "You have 1 active feed", result
  end

  test "#feed_summary_line should handle single inactive count" do
    result = feed_summary_line(active_count: 0, inactive_count: 3, draft_count: 0)
    assert_equal "You have 3 inactive feeds", result
  end

  test "#feed_summary_line should handle only draft count" do
    result = feed_summary_line(active_count: 0, inactive_count: 0, draft_count: 1)
    assert_equal "You have 1 draft feed", result
  end

  test "#feed_summary_line should describe active and draft counts" do
    result = feed_summary_line(active_count: 2, inactive_count: 0, draft_count: 1)
    assert_equal "You have 2 active feeds and 1 draft feed", result
  end

  test "#feed_summary_line should return nil for zero counts" do
    assert_nil feed_summary_line(active_count: 0, inactive_count: 0, draft_count: 0)
  end

  test "#feed_status_badge should render enabled badge for enabled feed" do
    feed = build(:feed, :enabled)
    result = feed_status_badge(feed)

    assert_equal "Enabled", result.instance_variable_get(:@text)
    assert_equal :green, result.instance_variable_get(:@color)
  end

  test "#feed_status_badge should render disabled badge for disabled feed" do
    feed = build(:feed, :disabled)
    result = feed_status_badge(feed)

    assert_equal "Disabled", result.instance_variable_get(:@text)
    assert_equal :yellow, result.instance_variable_get(:@color)
  end

  test "#feed_status_badge should render draft badge for draft feed" do
    feed = build(:feed, :draft)
    result = feed_status_badge(feed)

    assert_equal "Draft", result.instance_variable_get(:@text)
    assert_equal :gray, result.instance_variable_get(:@color)
  end

  test "#feed_actions_menu_items should list refresh, edit, purge, and delete for an enabled feed" do
    feed = create(:feed, :enabled, target_group: "testgroup")

    labels = feed_actions_menu_items(feed).map { |item| item[:label] }

    assert_equal ["Refresh", "Edit", "Purge feed…", "Delete feed…"], labels
  end

  test "#feed_actions_menu_items should omit refresh for a feed that is not enabled" do
    feed = create(:feed, :disabled, target_group: "testgroup")

    labels = feed_actions_menu_items(feed).map { |item| item[:label] }

    assert_equal ["Edit", "Purge feed…", "Delete feed…"], labels
  end

  test "#feed_actions_menu_items should omit purge when the feed has no target group" do
    feed = create(:feed, :enabled, target_group: "testgroup")
    feed.target_group = nil

    labels = feed_actions_menu_items(feed).map { |item| item[:label] }

    assert_equal ["Refresh", "Edit", "Delete feed…"], labels
  end

  test "#feed_actions_menu_items should wire refresh to a POST and danger actions to their modals" do
    feed = create(:feed, :enabled, target_group: "testgroup")

    items = feed_actions_menu_items(feed).index_by { |item| item[:label] }

    assert_equal :post, items["Refresh"][:method]
    assert_equal feed_refresh_path(feed), items["Refresh"][:href]
    assert_equal "purge-modal-#{feed.id}", items["Purge feed…"].dig(:data, :modal_trigger_modal_id_value)
    assert_equal "delete-feed-modal-#{feed.id}", items["Delete feed…"].dig(:data, :modal_trigger_modal_id_value)
  end

  test "#feed_missing_enablement_parts should not report source missing for query-type feed with query" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: "testgroup",
                        feed_profile_key: "llm_web_search",
                        params: { "query" => "climate change news" })
    result = feed_missing_enablement_parts(feed)

    assert_not_includes result, "source"
  end

  test "#feed_missing_enablement_parts should report source missing when neither url nor query present" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: "testgroup",
                        params: {})
    result = feed_missing_enablement_parts(feed)

    assert_includes result, "source"
  end

  test "#candidate_summary should fall back to the profile display name for URL profiles" do
    assert_equal "RSS Feed", candidate_summary("rss", "https://example.com/feed.xml")
    assert_equal "AI page reader", candidate_summary("llm_website_extractor", "https://example.com")
  end

  test "#candidate_summary should personalize the web-search profile with the user's input" do
    assert_equal "Follow AI search results for \"climate change\"",
                 candidate_summary("llm_web_search", "climate change")
  end

  test "#candidate_summary should personalize the web-search profile with a handle input" do
    assert_equal "Follow AI search results for \"@alice\"",
                 candidate_summary("llm_web_search", "@alice")
  end
end
