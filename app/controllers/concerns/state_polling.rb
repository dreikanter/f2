# Shared client-side polling settings for controllers that render a `polling`
# Stimulus host (state-tracking pages like token/credential validation, feed
# identification, and feed preview). Controllers that need a different poll cap
# override `polling_max_polls`.
module StatePolling
  extend ActiveSupport::Concern

  POLLING_INTERVAL_MS = 2000
  POLLING_MAX_POLLS = 35

  included do
    helper_method :polling_interval_ms, :polling_max_polls
  end

  def polling_interval_ms
    POLLING_INTERVAL_MS
  end

  def polling_max_polls
    POLLING_MAX_POLLS
  end
end
