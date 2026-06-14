# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Run in clustered mode only in deployed environments. Workers are forked web
# server processes; with the GVL, parallelism across CPU cores comes from
# workers, not threads, so clustering is how the multi-core production host uses
# both cores. Development and test stay single-process to keep code reloading
# working and avoid fork overhead. Set WEB_CONCURRENCY to scale the worker count
# (see config/deploy.production.yml).
if %w[production staging].include?(ENV.fetch("RAILS_ENV", "development"))
  workers ENV.fetch("WEB_CONCURRENCY", 1)

  # Preload the application before forking workers so they share memory via
  # copy-on-write, reducing total memory footprint. Active Record reconnects
  # automatically in each forked worker.
  preload_app!

  # The metrics flusher thread starts in the master during preload and does not
  # survive the fork, so each worker restarts its own. Gauges are global DB
  # snapshots sampled once by the master process; workers skip them and push
  # only their per-process counters. All a no-op unless metrics are enabled
  # (METRICS_URL). See config/initializers/metrics.rb.
  on_worker_boot do
    Metrics.skip_gauges!
    Metrics.start!
  end
end

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
