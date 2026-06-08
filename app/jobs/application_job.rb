class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # Count every job run by outcome. Throttles are tracked separately from real
  # failures since RateLimited reschedules them (they aren't errors).
  around_perform do |job, block|
    block.call
    Metrics.increment("job_executions_total", job: job.class.name, status: "ok")
  rescue RateLimit::Throttled
    Metrics.increment("job_executions_total", job: job.class.name, status: "throttled")
    raise
  rescue StandardError
    Metrics.increment("job_executions_total", job: job.class.name, status: "error")
    raise
  end
end
