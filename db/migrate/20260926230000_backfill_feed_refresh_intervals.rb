class BackfillFeedRefreshIntervals < ActiveRecord::Migration[8.2]
  LEGACY_INTERVALS = {
    "*/10 * * * *" => 600,
    "*/20 * * * *" => 1_200,
    "*/30 * * * *" => 1_800,
    "0 * * * *" => 3_600,
    "0 */2 * * *" => 7_200,
    "0 */6 * * *" => 21_600,
    "0 */12 * * *" => 43_200,
    "0 0 * * *" => 86_400,
    "0 0 */2 * *" => 172_800
  }.freeze

  def up
    LEGACY_INTERVALS.each do |cron, interval|
      execute <<~SQL
        UPDATE feeds
        SET refresh_interval = #{interval}, cron_expression = NULL
        WHERE cron_expression = #{connection.quote(cron)}
      SQL
    end
  end

  def down
    LEGACY_INTERVALS.each do |cron, interval|
      execute <<~SQL
        UPDATE feeds
        SET cron_expression = #{connection.quote(cron)}, refresh_interval = NULL
        WHERE refresh_interval = #{interval} AND cron_expression IS NULL
      SQL
    end
  end
end
