require "test_helper"

class FeedScheduleTest < ActiveSupport::TestCase
  test "should be valid with feed association" do
    schedule = build(:feed_schedule)
    assert schedule.valid?
  end

  test "should require feed" do
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

  test "#calculate_next_run_at should handle daily cron" do
    feed = build(:feed, cron_expression: "0 9 * * *")
    schedule = build(:feed_schedule, feed: feed)

    freeze_time do
      next_run = schedule.calculate_next_run_at
      assert next_run.is_a?(Time)
    end
  end

  test "#calculate_next_run_at should handle hourly cron" do
    feed = build(:feed, cron_expression: "0 * * * *")
    schedule = build(:feed_schedule, feed: feed)

    freeze_time do
      next_run = schedule.calculate_next_run_at
      assert next_run.is_a?(Time)
    end
  end
end
