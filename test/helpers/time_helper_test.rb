require "test_helper"

class TimeHelperTest < ActionView::TestCase
  include TimeHelper

  test "short_time_ago returns nil for nil input" do
    assert_nil short_time_ago(nil)
  end

  test "short_time_ago returns seconds for recent time" do
    time = 30.seconds.ago
    assert_equal "30s", short_time_ago(time)
  end

  test "short_time_ago returns minutes for time within hour" do
    time = 15.minutes.ago
    assert_equal "15m", short_time_ago(time)
  end

  test "short_time_ago returns hours for time within day" do
    time = 5.hours.ago
    assert_equal "5h", short_time_ago(time)
  end

  test "short_time_ago returns days for time within month" do
    time = 10.days.ago
    assert_equal "10d", short_time_ago(time)
  end

  test "short_time_ago returns months for time within year" do
    time = 3.months.ago
    assert_equal "3mo", short_time_ago(time)
  end

  test "short_time_ago returns years for old time" do
    time = 2.years.ago
    assert_equal "2y", short_time_ago(time)
  end

  test "long_time_format returns nil for nil input" do
    assert_nil long_time_format(nil)
  end

  test "long_time_format returns formatted time string" do
    time = Time.zone.parse("2025-01-15 15:45:30")
    assert_equal "15 Jan 2025, 15:45", long_time_format(time)
  end

  test "long_time_format handles single digit day" do
    time = Time.zone.parse("2025-01-01 09:30:00")
    assert_equal "1 Jan 2025, 09:30", long_time_format(time)
  end

  test "time_ago_tag returns nil for nil input" do
    assert_nil time_ago_tag(nil)
  end

  test "time_ago_tag generates HTML time element" do
    time = Time.zone.parse("2025-01-15 15:45:30")
    travel_to Time.zone.parse("2025-01-15 16:45:30") do
      result = time_ago_tag(time)
      assert_includes result, "<time"
      assert_includes result, 'datetime="2025-01-15T15:45:30Z"'
      assert_includes result, 'title="15 Jan 2025, 15:45"'
      assert_includes result, "about 1 hour ago"
    end
  end
end
