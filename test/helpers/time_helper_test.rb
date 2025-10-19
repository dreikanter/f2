require "test_helper"

class TimeHelperTest < ActiveSupport::TestCase
  include TimeHelper
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::TagHelper
  include ActiveSupport::Testing::TimeHelpers

  test "short_time_ago returns nil for nil input" do
    assert_nil short_time_ago(nil)
  end

  test "short_time_ago returns seconds for recent time" do
    travel_to Time.zone.parse("2025-01-15 15:45:30") do
      time = 30.seconds.ago
      assert_equal "30s", short_time_ago(time)
    end
  end

  test "short_time_ago returns minutes for time within hour" do
    travel_to Time.zone.parse("2025-01-15 15:45:30") do
      time = 15.minutes.ago
      assert_equal "15m", short_time_ago(time)
    end
  end

  test "short_time_ago returns hours for time within day" do
    travel_to Time.zone.parse("2025-01-15 15:45:30") do
      time = 5.hours.ago
      assert_equal "5h", short_time_ago(time)
    end
  end

  test "short_time_ago returns days for time within month" do
    travel_to Time.zone.parse("2025-01-15 15:45:30") do
      time = 10.days.ago
      assert_equal "10d", short_time_ago(time)
    end
  end

  test "short_time_ago returns months for time within year" do
    travel_to Time.zone.parse("2025-01-15 15:45:30") do
      time = 3.months.ago
      assert_equal "3mo", short_time_ago(time)
    end
  end

  test "short_time_ago returns years for old time" do
    travel_to Time.zone.parse("2025-01-15 15:45:30") do
      time = 2.years.ago
      assert_equal "2y", short_time_ago(time)
    end
  end

  test "long_time_format returns nil for nil input" do
    assert_nil long_time_format(nil)
  end

  test "long_time_format returns formatted time string" do
    travel_to Time.zone.parse("2025-01-15 15:45:30") do
      time = Time.zone.parse("2025-01-15 15:45:30")
      assert_equal "15 Jan 2025, 15:45", long_time_format(time)
    end
  end

  test "long_time_format handles single digit day" do
    travel_to Time.zone.parse("2025-01-01 09:30:00") do
      time = Time.zone.parse("2025-01-01 09:30:00")
      assert_equal "1 Jan 2025, 09:30", long_time_format(time)
    end
  end

  test "time_ago_tag returns nil for nil input" do
    assert_nil time_ago_tag(nil)
  end

  test "time_ago_tag generates HTML time element" do
    time = Time.zone.parse("2025-01-15 15:45:30")

    travel_to Time.zone.parse("2025-01-15 16:45:30") do
      result = time_ago_tag(time)
      expected = '<time datetime="2025-01-15T15:45:30Z" title="15 Jan 2025, 15:45">about 1 hour ago</time>'
      assert_equal expected, result
    end
  end

  test "long_time_tag returns nil for nil input" do
    assert_nil long_time_tag(nil)
  end

  test "long_time_tag generates HTML time element" do
    time = Time.zone.parse("2025-01-15 15:45:30")

    travel_to Time.zone.parse("2025-01-15 16:45:30") do
      result = long_time_tag(time)
      expected = '<time datetime="2025-01-15T15:45:30Z" title="about 1 hour ago">15 Jan 2025, 15:45</time>'
      assert_equal expected, result
    end
  end

  test "short_time_ago_tag returns nil for nil input" do
    assert_nil short_time_ago_tag(nil)
  end

  test "short_time_ago_tag generates HTML time element with short format" do
    time = Time.zone.parse("2025-01-15 15:45:30")

    travel_to Time.zone.parse("2025-01-15 17:45:30") do
      result = short_time_ago_tag(time)
      expected = '<time datetime="2025-01-15T15:45:30Z" title="15 Jan 2025, 15:45">2h</time>'
      assert_equal expected, result
    end
  end
end
