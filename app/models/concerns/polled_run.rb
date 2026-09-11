# Shared timing for background runs the browser polls while they are in
# flight, plus the compare-and-set a scheduled timeout uses to settle one.
module PolledRun
  extend ActiveSupport::Concern

  POLLING_INTERVAL_MS = 2500
  TIMEOUT_AFTER = 85.seconds

  class_methods do
    # The first poll is immediate. Two extra polls leave one interval for Solid
    # Queue to dispatch a due timeout and let the final poll render its result.
    def polls_within(timeout)
      timeout.in_milliseconds.div(POLLING_INTERVAL_MS) + 2
    end

    def polling_max_polls
      polls_within(TIMEOUT_AFTER)
    end
  end

  # Settle a run only while its token still matches, so a superseded run's
  # timeout lands on nothing. Rotating the token stops the worker that owned
  # the run from writing a result afterwards.
  # @param run_id [String] the run token captured when the timeout was scheduled
  # @param status [Symbol] the status a timed-out run settles into
  # @param from [Symbol, Array<Symbol>] statuses a timeout may still settle
  # @return [self] the record, reloaded when this call won the transition
  def settle_timeout!(run_id:, status:, from:)
    updated = self.class.where(id: id, run_id: run_id, status: from)
                  .update_all(status: status, run_id: SecureRandom.uuid, updated_at: Time.current)
    reload if updated.positive?
    self
  end
end
