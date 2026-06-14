# Polling settings for controllers that render a `polling` Stimulus host
# (token/credential validation, feed identification, feed preview). Interval and
# cap are exposed to views and overridable per controller via class_attribute.
module StatePolling
  extend ActiveSupport::Concern

  included do
    class_attribute :polling_interval_ms, default: 2500, instance_writer: false
    class_attribute :polling_max_polls, default: 36, instance_writer: false

    helper_method :polling_interval_ms, :polling_max_polls
  end

  # Server-side deadline, set just before the client's final poll so that poll
  # still renders the outcome instead of leaving the spinner frozen. The first
  # poll is immediate, so the last lands at (max_polls - 1) * interval.
  def polling_timeout
    ((polling_max_polls - 2) * polling_interval_ms).fdiv(1000).seconds
  end
end
