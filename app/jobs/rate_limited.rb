# Throttle handling for jobs that reserve RateLimit capacity.
#
# Throttling is control flow, not failure: "no capacity now, come back later".
# Jobs call the non-raising RateLimit.acquire and, when denied, defer via
# reschedule_for_rate_limit. A real mid-call 429 still raises RateLimit::Throttled;
# jobs rescue it locally and route it through the same helper. Handled inside
# `perform`, a deferral never reaches the error reporter — only a give-up does.
#
# Reschedules wait retry_after (plus jitter), up to MAX_ATTEMPTS, then report
# once and stop.
module RateLimited
  MAX_ATTEMPTS = 10
  JITTER_SECONDS = 5

  # True once this run has deferred itself for rate limiting. The observability
  # layer (ApplicationJob) reads it to count the run as throttled rather than ok.
  def rate_limited?
    @rate_limited == true
  end

  private

  # Defer this run because there's no capacity. Reschedules with backoff until
  # the attempt cap, then reports the throttle once and invokes the cleanup hook.
  def reschedule_for_rate_limit(retry_after)
    @rate_limited = true

    if executions < MAX_ATTEMPTS
      retry_job(wait: retry_after + rand(0.0..JITTER_SECONDS))
    else
      error = RateLimit::Throttled.new(retry_after: retry_after)
      Rails.error.report(error, context: { job: self.class.name, arguments: arguments })
      on_rate_limit_exhausted(error)
    end
  end

  # Hook for jobs to clean up any in-progress state left behind when the
  # throttle retries are exhausted. Default is a no-op.
  def on_rate_limit_exhausted(error)
  end
end
