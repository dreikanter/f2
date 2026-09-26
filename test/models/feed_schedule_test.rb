require "test_helper"

class FeedScheduleTest < ActiveSupport::TestCase
  test "#valid? should return true with feed association" do
    schedule = build(:feed_schedule)
    assert schedule.valid?
  end

  test "#valid? should require feed" do
    schedule = build(:feed_schedule, feed: nil)
    assert_not schedule.valid?
    assert schedule.errors.of_kind?(:feed, :blank)
  end

  test "#calculate_next_run_at should parse cron expression" do
    feed = build(:feed, cron_expression: "0 */6 * * *")
    schedule = build(:feed_schedule, feed: feed)

    freeze_time do
      next_run = schedule.calculate_next_run_at
      assert next_run.is_a?(Time)
      assert next_run > Time.current
    end
  end

  test "#calculate_next_run_at should spread a new interval schedule across its first interval" do
    feed = build(:feed, cron_expression: nil, refresh_interval: 2.hours.to_i)
    schedule = build(:feed_schedule, feed: feed)

    freeze_time do
      next_run = schedule.calculate_next_run_at

      assert_operator next_run, :>, Time.current
      assert_operator next_run, :<=, 2.hours.from_now
    end
  end

  test "#calculate_next_run_at should preserve interval phase while skipping missed slots" do
    travel_to Time.utc(2026, 9, 26, 12) do
      feed = build(:feed, cron_expression: nil, refresh_interval: 2.hours.to_i)
      schedule = build(:feed_schedule, feed: feed, next_run_at: 5.hours.ago)

      assert_equal 1.hour.from_now, schedule.calculate_next_run_at
    end
  end
end
