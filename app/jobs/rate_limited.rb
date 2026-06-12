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

  # Reported (never raised) when a job gives up after MAX_ATTEMPTS throttled
  # runs. A distinct class because RateLimit::Throttled itself is on
  # Honeybadger's ignore list as expected backpressure.
  class RetriesExhausted < StandardError; end

  included do
    rescue_from(RateLimit::Throttled) do |error|
      if executions < MAX_ATTEMPTS
        retry_job(wait: error.retry_after + rand(0.0..JITTER_SECONDS))
      else
        report_exhausted(error)
        on_rate_limit_exhausted(error)
      end
    end
  end

  private

  def report_exhausted(error)
    exhausted = RetriesExhausted.new("#{self.class.name} gave up after #{executions} throttled runs: #{error.message}")
    exhausted.set_backtrace(error.backtrace)
    Rails.error.report(exhausted, context: { job: self.class.name, arguments: arguments })
  end

  # Hook for jobs to clean up any in-progress state left behind when the
  # throttle retries are exhausted. Default is a no-op.
  def on_rate_limit_exhausted(error)
  end
end
