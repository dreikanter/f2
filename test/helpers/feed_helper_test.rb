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

  test "#feed_status_icon should render enabled icon" do
    feed = build(:feed, :enabled)

    result = feed_status_icon(feed)

    assert_includes result, "<svg"
    assert_includes result, "text-emerald-500"
    assert_includes result, 'title="Enabled"'
    assert_includes result, 'aria-label="Enabled"'
    assert_includes result, 'role="img"'
  end

  test "#feed_status_icon should render disabled icon" do
    feed = build(:feed, :disabled)

    result = feed_status_icon(feed)

    assert_includes result, "<svg"
    assert_includes result, "text-slate-400"
    assert_includes result, 'title="Disabled"'
    assert_includes result, 'aria-label="Disabled"'
    assert_includes result, 'role="img"'
  end

  test "#feed_status_icon should render draft icon" do
    feed = build(:feed, :draft)

    result = feed_status_icon(feed)

    assert_includes result, "<svg"
    assert_includes result, "text-amber-500"
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

  test "#feed_status_summary should describe enabled feed" do
    feed = build(:feed, :enabled)
    expected = "This feed is enabled and will continue to import items on its schedule."

    assert_equal expected, feed_status_summary(feed)
  end

  test "#feed_status_summary should describe ready feed" do
    feed = build(:feed)
    expected = "This feed is ready to enable. Turn it on to start importing posts."

    assert_equal expected, feed_status_summary(feed)
  end

  test "#feed_status_summary should list missing parts" do
    feed = build(:feed, :without_access_token)
    expected = "This feed is currently disabled. Add active access token and target group to finish setup."

    assert_equal expected, feed_status_summary(feed)
  end

  test "#feed_status_summary should handle disabled feed without missing parts" do
    feed = build(:feed, :disabled)
    feed.define_singleton_method(:can_be_enabled?) { false }

    expected = "This feed is currently disabled."

    self.stub(:feed_missing_enablement_parts, ->(_feed) { [] }) do
      assert_equal expected, feed_status_summary(feed)
    end
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
