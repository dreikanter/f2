require "test_helper"

class EventsHelperTest < ActionView::TestCase
  include TimeHelper

  test "#admin_event_filter_summary renders a direct link for a known subject type" do
    subject_id = SecureRandom.uuid

    result = admin_event_filter_summary({ subject_type: "Feed", subject_id: subject_id })
    fragment = Nokogiri::HTML.fragment(result)
    link = fragment.at_css("a")

    assert_equal "subject_type: Feed • subject_id: #{subject_id.last(5)}", fragment.text
    assert_equal admin_feed_path(subject_id), link["href"]
    assert_equal subject_id, link["title"]
  end

  test "#admin_event_filter_summary leaves an unknown subject type unlinked" do
    subject_id = SecureRandom.uuid

    result = admin_event_filter_summary({ subject_type: "Post", subject_id: subject_id })
    fragment = Nokogiri::HTML.fragment(result)
    label = fragment.at_css("span")

    assert_equal "subject_type: Post • subject_id: #{subject_id.last(5)}", fragment.text
    assert_equal subject_id, label["title"]
    assert_nil fragment.at_css("a")
  end

  test "#format_event_duration should format seconds under a minute" do
    assert_equal "3.2s", format_event_duration(3.2)
    assert_equal "59.0s", format_event_duration(59.0)
    assert_equal "0.0s", format_event_duration(0.0)
  end

  test "#format_event_duration should format seconds as minutes and seconds when 60 or more" do
    assert_equal "1m 35s", format_event_duration(95.0)
    assert_equal "2m 0s", format_event_duration(120.0)
    assert_equal "10m 3s", format_event_duration(603.4)
  end

  test "#format_stat_value should format _at keys as time tags" do
    time_str = "2026-06-17T10:00:00Z"

    result = format_stat_value("started_at", time_str)

    assert_includes result, "<time"
    assert_includes result, time_str
  end

  test "#format_stat_value should return raw value for unparseable _at keys" do
    result = format_stat_value("started_at", "not-a-date")

    assert_equal "not-a-date", result
  end

  test "#format_stat_value should format total_duration using format_event_duration" do
    assert_equal "12.3s", format_stat_value("total_duration", 12.34)
    assert_equal "1m 35s", format_stat_value("total_duration", 95.0)
  end

  test "#format_stat_value should format integer values with delimiters" do
    assert_equal "1,234,567", format_stat_value("content_size", 1234567)
    assert_equal "12,500", format_stat_value("total_entries", 12500)
    assert_equal "5", format_stat_value("new_posts", 5)
  end

  test "#format_stat_value should format step duration keys" do
    assert_equal "12.8s", format_stat_value("load_feed_contents_duration", 12.845)
    assert_equal "1m 35s", format_stat_value("persist_posts_duration", 95.0)
  end

  test "#format_stat_value should format _cents keys as currency" do
    assert_equal "$0.03", format_stat_value("llm_cost_cents", 3)
    assert_equal "$12.00", format_stat_value("llm_cost_cents", 1200)
    assert_equal "$0.00", format_stat_value("llm_cost_cents", 0)
  end

  test "#format_stat_value should return value as-is for other keys" do
    assert_equal "foo", format_stat_value("some_key", "foo")
  end
end
