# Samples Postgres size statistics for the metrics gauges. Queries run at
# metrics push time on the flusher thread, never at boot, so the app can
# start without a database; with_connection returns the connection to the
# pool between samples.
module PostgresMetrics
  module_function

  def database_size
    ApplicationRecord.with_connection do |connection|
      connection.select_value("SELECT pg_database_size(current_database())")
    end
  end

  def table_sizes
    rows = ApplicationRecord.with_connection do |connection|
      connection.select_rows("SELECT relname, pg_total_relation_size(relid) FROM pg_stat_user_tables")
    end
    rows.to_h { |table, size| [{ table: table }, size] }
  end
end
