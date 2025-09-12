require "test_helper"

class EventsHelperTest < ActionView::TestCase
  test "level_badge returns single character badge with correct styling" do
    badge = level_badge("info")

    assert_includes badge, "I"
    assert_includes badge, "badge bg-primary"
    assert_includes badge, "font-monospace"
    assert_includes badge, 'title="Info"'
  end

  test "level_badge handles all level types" do
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

  test "level_badge falls back to debug for unknown level" do
    badge = level_badge("unknown")

    assert_includes badge, "D"
    assert_includes badge, "bg-secondary"
  end

  test "level_badge_full returns full word badge with correct styling" do
    badge = level_badge_full("info")

    assert_includes badge, "Info"
    assert_includes badge, "badge bg-primary"
    refute_includes badge, "font-monospace"
  end

  test "level_badge_full handles all level types" do
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

  test "compact_time_ago returns seconds for times under 1 minute" do
    time = 30.seconds.ago
    result = compact_time_ago(time)
    assert_equal "30s", result
  end

  test "compact_time_ago returns minutes for times under 1 hour" do
    time = 15.minutes.ago
    result = compact_time_ago(time)
    assert_equal "15m", result
  end

  test "compact_time_ago returns hours for times under 1 day" do
    time = 8.hours.ago
    result = compact_time_ago(time)
    assert_equal "8h", result
  end

  test "compact_time_ago returns days for times under 30 days" do
    time = 5.days.ago
    result = compact_time_ago(time)
    assert_equal "5d", result
  end

  test "compact_time_ago returns months for times over 30 days" do
    time = 45.days.ago
    result = compact_time_ago(time)
    assert_equal "1mo", result
  end

  test "compact_time_ago handles edge cases" do
    # Just now
    time = Time.current
    result = compact_time_ago(time)
    assert_equal "0s", result

    # Exactly 1 minute
    time = 60.seconds.ago
    result = compact_time_ago(time)
    assert_equal "1m", result

    # Exactly 1 hour
    time = 1.hour.ago
    result = compact_time_ago(time)
    assert_equal "1h", result

    # Exactly 1 day
    time = 1.day.ago
    result = compact_time_ago(time)
    assert_equal "1d", result
  end
end
