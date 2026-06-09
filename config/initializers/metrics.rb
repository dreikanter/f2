# Register sampled gauges and start the metrics push loop. The whole thing is a
# no-op unless METRICS_URL is set, so dev, test, and console runs do nothing.
# See app/services/metrics.rb.
Rails.application.config.after_initialize do
  next unless Metrics.enabled?

  Metrics.gauge("users_active") { User.where(state: :active).count }
  Metrics.gauge("feeds_enabled") { Feed.where(state: :enabled).count }
  Metrics.gauge("posts_enqueued") { Post.enqueued.count }
  Metrics.gauge("jobs_ready") { SolidQueue::ReadyExecution.count }
  Metrics.gauge("pg_database_size_bytes") { PostgresMetrics.database_size }
  Metrics.gauge_set("pg_table_size_bytes") { PostgresMetrics.table_sizes }

  Metrics.start!

  # SolidQueue forks worker processes; threads don't survive fork, so the flush
  # thread must be restarted inside each worker after the fork.
  SolidQueue.on_worker_start { Metrics.start! }
end
