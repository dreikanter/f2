# Server-side half of the "poll until a background job finishes" pattern. The
# JS `polling` Stimulus controller drives the request loop; this concern owns
# the cadence it runs at and the rule for when the server should stay silent.
#
# Cadence lives here rather than on the model because it describes polling
# behavior, not domain data. PollingShellComponent reads these constants as its
# defaults; a controller whose work runs longer hands a different value to the
# component instead.
module StatePolling
  extend ActiveSupport::Concern

  # Re-poll every two seconds; the client gives up after ~70s and shows the
  # "taking longer than expected" message.
  POLLING_INTERVAL_MS = 2000
  POLLING_MAX_POLLS = 35

  private

  # True while the background job is still in flight. Controllers answer with
  # `head :no_content` in that window so the poller keeps the spinner it already
  # drew instead of redrawing (and restarting) it every cycle. Override when a
  # record's in-progress states differ from the default pending/validating pair.
  def keep_polling?(record)
    record.pending? || record.validating?
  end
end
