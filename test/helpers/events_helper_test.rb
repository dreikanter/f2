require "test_helper"

class EventsHelperTest < ActionView::TestCase
  include TimeHelper

  test "#level_badge should return single character badge with correct styling" do
    badge = level_badge("info")

    assert_includes badge, "I"
    assert_includes badge, "badge bg-primary"
    assert_includes badge, "font-monospace"
    assert_includes badge, 'title="Info"'
  end

  test "#level_badge should handle all level types" do
    debug_badge = level_badge("debug")
    info_badge = level_badge("info")
    warning_badge = level_badge("warning")
    error_badge = level_badge("error")

    assert_includes debug_badge, "D"
    assert_includes debug_badge, "bg-secondary"

    assert_includes info_badge, "I"
    assert_includes info_badge, "bg-primary"

    assert_includes warning_badge, "W"
    assert_includes warning_badge, "bg-warning"

    assert_includes error_badge, "E"
    assert_includes error_badge, "bg-danger"
  end

  test "#level_badge should fall back to debug for unknown level" do
    badge = level_badge("unknown")

    assert_includes badge, "D"
    assert_includes badge, "bg-secondary"
  end

  test "#level_badge_full should return full word badge with correct styling" do
    badge = level_badge_full("info")

    assert_includes badge, "Info"
    assert_includes badge, "badge bg-primary"
    refute_includes badge, "font-monospace"
  end

  test "#level_badge_full should handle all level types" do
    debug_badge = level_badge_full("debug")
    info_badge = level_badge_full("info")
    warning_badge = level_badge_full("warning")
    error_badge = level_badge_full("error")

    assert_includes debug_badge, "Debug"
    assert_includes debug_badge, "bg-secondary"

    assert_includes info_badge, "Info"
    assert_includes info_badge, "bg-primary"

    assert_includes warning_badge, "Warning"
    assert_includes warning_badge, "bg-warning"

    assert_includes error_badge, "Error"
    assert_includes error_badge, "bg-danger"
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

  test "#format_stat_value should return value as-is for other keys" do
    assert_equal 5, format_stat_value("new_posts", 5)
    assert_equal "foo", format_stat_value("some_key", "foo")
  end
end
