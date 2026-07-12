require "test_helper"

class EventsHelperTest < ActionView::TestCase
  include TimeHelper

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
