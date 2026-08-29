# Polling settings for controllers that render a `polling` Stimulus host
# (token/credential validation and groups refresh). Interval and
# cap are exposed to views and overridable per controller via class_attribute.
module StatePolling
  extend ActiveSupport::Concern

  included do
    class_attribute :polling_interval_ms, default: 2500, instance_writer: false
    class_attribute :polling_max_polls, default: 36, instance_writer: false

    helper_method :polling_interval_ms, :polling_max_polls
  end
end
