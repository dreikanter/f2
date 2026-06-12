# Register sampled gauges and start the metrics push loop. The whole thing is a
# no-op unless METRICS_URL is set, so dev, test, and console runs do nothing.
# See app/services/metrics.rb.
Rails.application.config.after_initialize do
  next unless Metrics.enabled?

  # Gauges are global DB snapshots, so a single process samples them — the one
  # with METRICS_GAUGES set (the web role; see config/deploy.staging.yml).
  # Without the gate every process (Puma, SolidQueue supervisor, each worker)
  # would run identical queries every flush and overwrite the same series.
  # Counters are per-process and register/push everywhere regardless.
  if ENV["METRICS_GAUGES"].present?
    Metrics.gauge("users_active") { User.where(state: :active).count }
    Metrics.gauge("feeds_enabled") { Feed.where(state: :enabled).count }
    Metrics.gauge_set("posts_total") do
      counts = Post.group(:status).count
      Post.statuses.keys.to_h { |status| [{ status: status }, counts.fetch(status, 0)] }
    end
    Metrics.gauge("jobs_ready") { SolidQueue::ReadyExecution.count }
    Metrics.gauge("pg_database_size_bytes") { PostgresMetrics.database_size }
    Metrics.gauge_set("pg_table_size_bytes") { PostgresMetrics.table_sizes }
  end

  Metrics.start!

  # SolidQueue forks worker processes; threads don't survive fork, so the flush
  # thread must be restarted inside each worker after the fork.
  SolidQueue.on_worker_start { Metrics.start! }
end
