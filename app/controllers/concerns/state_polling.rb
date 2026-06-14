# Shared client-side polling settings for controllers that render a `polling`
# Stimulus host (state-tracking pages like token/credential validation, feed
# identification, and feed preview). Controllers that need a different poll cap
# reassign `self.polling_max_polls` in their class body.
module StatePolling
  extend ActiveSupport::Concern

  included do
    class_attribute :polling_interval_ms, default: 2000, instance_writer: false
    class_attribute :polling_max_polls, default: 35, instance_writer: false

    helper_method :polling_interval_ms, :polling_max_polls
  end
end
