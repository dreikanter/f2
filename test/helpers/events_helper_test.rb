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

  test "compact_time_ago delegates to short_time_ago" do
    time = 30.seconds.ago
    assert_equal short_time_ago(time), compact_time_ago(time)
  end
end
