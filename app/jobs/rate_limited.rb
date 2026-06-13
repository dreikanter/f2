# Throttle handling for jobs that reserve RateLimit capacity.
#
# Rate limiting here is control flow, not failure: "no capacity right now, come
# back later". So jobs ask RateLimit.acquire (the non-raising variant) and, when
# it's not allowed, call reschedule_for_rate_limit to defer themselves. The rare
# case where FreeFeed itself returns a 429 mid-call still arrives as a raised
# RateLimit::Throttled; jobs rescue it locally and route it through the same
# helper. Either way the deferral is handled inside `perform`, so it never
# surfaces to the error reporter as a fault — only a genuine give-up does.
#
# Reschedules wait the limiter's retry_after (plus jitter to avoid stampedes),
# up to MAX_ATTEMPTS. After that it reports once and stops; the recurring
# schedulers re-kick the work later, so giving up is not permanent.
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
