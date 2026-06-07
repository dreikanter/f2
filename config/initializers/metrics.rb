# Register sampled gauges and start the metrics push loop. The whole thing is a
# no-op unless METRICS_URL is set, so dev, test, and console runs do nothing.
# See app/services/metrics.rb.
Rails.application.config.after_initialize do
  next unless Metrics.enabled?

  Metrics.gauge("users_active") { User.where(state: :active).count }
  Metrics.gauge("feeds_enabled") { Feed.where(state: :enabled).count }
  Metrics.gauge("posts_enqueued") { Post.enqueued.count }
  Metrics.gauge("jobs_ready") { SolidQueue::ReadyExecution.count }

  Metrics.start!
end
