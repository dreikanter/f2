require "test_helper"

class FeedHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "feed_missing_enablement_parts returns both missing parts" do
    feed = build(:feed, :without_access_token)
    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token", "target group"], result
  end

  test "feed_missing_enablement_parts returns missing access token only" do
    feed = build(:feed, :without_access_token, target_group: "test_group")
    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token"], result
  end

  test "feed_missing_enablement_parts returns missing target group only" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: nil)
    result = feed_missing_enablement_parts(feed)

    assert_equal ["target group"], result
  end

  test "feed_missing_enablement_parts returns missing access token when inactive" do
    access_token = create(:access_token, :inactive)
    feed = build(:feed, access_token: access_token, target_group: "test_group")
    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token"], result
  end

  test "feed_missing_enablement_parts returns empty array when all requirements met" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: "test_group")
    result = feed_missing_enablement_parts(feed)

    assert_equal [], result
  end

  test "#feed_status_icon should render enabled icon" do
    feed = build(:feed, :enabled)

    result = feed_status_icon(feed)

    assert_includes result, "bi-check-circle-fill"
    assert_includes result, "text-emerald-500"
  end

  test "#feed_status_icon should render disabled icon" do
    feed = build(:feed, :disabled)

    result = feed_status_icon(feed)

    assert_includes result, "bi-x-circle"
    assert_includes result, "text-slate-400"
  end

  test "#feed_summary_line should describe active and inactive counts" do
    result = feed_summary_line(active_count: 2, inactive_count: 1)
    assert_equal "You have 2 active feeds and 1 inactive feed", result
  end

  test "#feed_summary_line should handle single active count" do
    result = feed_summary_line(active_count: 1, inactive_count: 0)
    assert_equal "You have 1 active feed", result
  end

  test "#feed_summary_line should handle single inactive count" do
    result = feed_summary_line(active_count: 0, inactive_count: 3)
    assert_equal "You have 3 inactive feeds", result
  end

  test "#feed_summary_line should return nil for zero counts" do
    assert_nil feed_summary_line(active_count: 0, inactive_count: 0)
  end
end
