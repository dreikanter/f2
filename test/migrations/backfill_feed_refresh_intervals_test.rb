require "test_helper"
require_relative "../../db/migrate/20260926230000_backfill_feed_refresh_intervals"

class BackfillFeedRefreshIntervalsTest < ActiveSupport::TestCase
  test "#up should convert and restore a legacy preset schedule" do
    feed = create(:feed, cron_expression: "0 */6 * * *", refresh_interval: nil)
    migration = BackfillFeedRefreshIntervals.new

    migration.migrate(:up)

    assert_equal 6.hours.to_i, feed.reload.refresh_interval
    assert_nil feed.cron_expression

    migration.migrate(:down)

    assert_nil feed.reload.refresh_interval
    assert_equal "0 */6 * * *", feed.cron_expression
  end
end
