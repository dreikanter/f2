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
# What an abandoned run tells us is that the check didn't happen — nothing about
# the token itself. So this settles the token's own state and stops there: the
# feeds behind it keep running. The window can't distinguish a dead run from a
# job still sitting in a badly backed-up queue, and that job may yet land and
# find the token perfectly good. Taking feeds down here would leave them down
# after it did, needing a human to put them back.
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

      access_token.update!(status: :inactive, validation_started_at: nil)
      record_event
    end

    true
  end

  private

  # Nothing else marks this: the token simply stops being checked. The log entry
  # is what tells the user why it went quiet, so it's written every time —
  # including for a token that has no feeds to speak for it.
  def record_event
    Event.create!(
      type: EVENT_TYPE,
      user: access_token.user,
      subject: access_token,
      level: :warning
    )
  end
end
