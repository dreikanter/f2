# Shared throttle handling for jobs that reserve RateLimit capacity.
#
# On RateLimit::Throttled, reschedules the job after the limiter's retry_after
# (plus a little jitter to avoid stampedes), up to MAX_ATTEMPTS. After that it
# reports and gives up — the recurring schedulers re-kick work later, so giving
# up is not permanent.
module RateLimited
  extend ActiveSupport::Concern

  MAX_ATTEMPTS = 10
  JITTER_SECONDS = 5

  included do
    rescue_from(RateLimit::Throttled) do |error|
      if executions < MAX_ATTEMPTS
        retry_job(wait: error.retry_after + rand(0.0..JITTER_SECONDS))
      else
        Rails.error.report(error, context: { job: self.class.name, arguments: arguments })
      end
    end
  end
end
