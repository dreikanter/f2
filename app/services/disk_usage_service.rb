require "open3"

class DiskUsageService
  def initialize(df_command: method(:execute_df_command))
    @df_command = df_command
  end

  def call
    {
      total_space: total_space,
      used_space: used_space,
      free_space: free_space,
      postgres_usage: postgres_usage,
      other_used_space: other_used_space,
      postgres_percentage: postgres_percentage,
      other_used_percentage: other_used_percentage,
      free_percentage: free_percentage,
      table_usage: table_usage,
      vacuum_stats: vacuum_stats,
      autovacuum_settings: autovacuum_settings
    }
  end

  private

  def disk_stats
    @disk_stats ||= begin
      out, status = @df_command.call
      raise "df command failed with status #{status.exitstatus}" unless status.success?

      parts = out.lines[1].split
      {
        total_kb: parts[1].to_i,
        used_kb: parts[2].to_i,
        avail_kb: parts[3].to_i
      }
    end
  end

  def execute_df_command
    Open3.capture2("df -Pk /") # POSIX format, KB units
  end

  def total_space
    disk_stats[:total_kb] * 1024
  end

  def used_space
    disk_stats[:used_kb] * 1024
  end

  def free_space
    disk_stats[:avail_kb] * 1024
  end

  def postgres_usage
    execute_query("SELECT pg_database_size(current_database())").first["pg_database_size"]
  end

  def other_used_space
    used_space - postgres_usage
  end

  def accountable_space
    # Use used + available as the base for percentage calculations
    # This excludes filesystem reserved space
    used_space + free_space
  end

  def postgres_percentage
    return 0.0 if accountable_space.zero?

    (postgres_usage.to_f / accountable_space * 100).round(1)
  end

  def other_used_percentage
    return 0.0 if accountable_space.zero?

    (other_used_space.to_f / accountable_space * 100).round(1)
  end

  def free_percentage
    return 0.0 if accountable_space.zero?

    (free_space.to_f / accountable_space * 100).round(1)
  end

  def table_usage
    execute_query(<<-SQL
      SELECT
        relname AS table_name,
        pg_size_pretty(pg_total_relation_size(pg_class.oid)) AS total_size
      FROM
        pg_class
        JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
      WHERE
        pg_namespace.nspname = 'public'
        AND pg_class.relkind = 'r'
      ORDER BY
        pg_total_relation_size(pg_class.oid) DESC;
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
