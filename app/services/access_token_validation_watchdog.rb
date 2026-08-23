# Settles token validations that nobody is going to finish.
#
# Starting a validation flips the token into an in-progress state and hands the
# rest to TokenValidationJob. When that run disappears — the worker is lost, a
# deploy cuts it short, the queue never picks it up — no one writes the outcome,
# and every page reading the token waits on a run that will never report back.
#
# The token page's validation poll is where that surfaces, so it asks for a
# reconciliation before reading. Doing it there rather than in a background
# sweep is deliberate: the queue is the thing that just failed, so the repair
# can't depend on it.
#
# An abandoned run tells us nothing about the token itself, only that the check
# didn't happen — so the token lands in the same failed state as a check that
# ran and said no, under an event type that names the real cause.
class AccessTokenValidationWatchdog
  EVENT_TYPE = "access_token_validation_abandoned".freeze

  attr_reader :access_token

  def initialize(access_token)
    @access_token = access_token
  end

  # True when this call settled the token.
  def call
    return false unless access_token.validation_abandoned?

    access_token.with_lock do
      # The lock waits; a real run may have finished in the meantime, and its
      # verdict is the one that counts.
      return false unless access_token.validation_abandoned?

      access_token.disable_token_and_feeds(event_type: EVENT_TYPE)
    end

    true
  end
end
