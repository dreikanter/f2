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

    assert_includes result, "bi-check-circle-fill"
    assert_includes result, "text-emerald-500"
    assert_includes result, 'title="Enabled"'
    assert_includes result, 'aria-label="Enabled"'
  end

  test "#feed_status_icon should render disabled icon" do
    feed = build(:feed, :disabled)

    result = feed_status_icon(feed)

    assert_includes result, "bi-x-circle"
    assert_includes result, "text-slate-400"
    assert_includes result, 'title="Disabled"'
    assert_includes result, 'aria-label="Disabled"'
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
end
