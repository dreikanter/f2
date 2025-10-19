require "open3"

class DiskUsageService
  def call
    {
      free_space: free_space,
      postgres_usage: postgres_usage,
      table_usage: table_usage,
      vacuum_stats: vacuum_stats,
      autovacuum_settings: autovacuum_settings
    }
  end

  private

  def free_space
    out, status = Open3.capture2("df -Pk /") # POSIX format, KB units
    raise "df command failed with status #{status.exitstatus}" unless status.success?

    avail_kb = out.lines[1].split[3].to_i
    avail_kb * 1024
  end

  def postgres_usage
    execute_query("SELECT pg_database_size(current_database())").first["pg_database_size"]
  end

  def table_usage
    execute_query(<<-SQL
      SELECT
        table_name,
        pg_size_pretty(pg_total_relation_size(quote_ident(table_name))) AS total_size
      FROM
        information_schema.tables
      WHERE
        table_schema = 'public'
      ORDER BY
        pg_total_relation_size(quote_ident(table_name)) DESC;
    SQL
    ).to_a
  end

  def vacuum_stats
    execute_query(<<-SQL
      SELECT
        relname,
        n_live_tup,
        n_dead_tup,
        last_vacuum,
        last_autovacuum,
        vacuum_count,
        autovacuum_count
      FROM
        pg_stat_user_tables
      ORDER BY
        n_dead_tup DESC;
    SQL
    ).to_a
  end

  def autovacuum_settings
    execute_query("SELECT name, setting FROM pg_settings WHERE name LIKE 'autovacuum%';").to_a
  end

  def execute_query(sql)
    ActiveRecord::Base.connection.execute(sql)
  end
end
