# Mounts the `polling` Stimulus controller on a stable host element and wraps
# the body it polls into. The host stays put across polls while the server
# swaps the inner `content_id` container (the Turbo Stream target); polling
# stops once a terminal body inside it carries the stop-condition marker
# (`data-polling-done` by default).
#
# Pass the terminal/loading body as the block, and an optional timeout notice
# via the `timeout_message` slot (shown when the client gives up). Cadence
# defaults to StatePolling's constants; override per call when a job runs
# longer.
class PollingShellComponent < ViewComponent::Base
  renders_one :timeout_message

  def initialize(
    endpoint:,
    content_id:,
    content_class: nil,
    content_target: false,
    stop_condition: "[data-polling-done]",
    interval: StatePolling::POLLING_INTERVAL_MS,
    max_polls: StatePolling::POLLING_MAX_POLLS,
    indicate_busy: true,
    timeout_class: nil
  )
    @endpoint = endpoint
    @content_id = content_id
    @content_class = content_class
    @content_target = content_target
    @stop_condition = stop_condition
    @interval = interval
    @max_polls = max_polls
    @indicate_busy = indicate_busy
    @timeout_class = timeout_class
  end

  private

  attr_reader :content_id, :content_class, :timeout_class

  def host_data
    {
      controller: "polling",
      polling_endpoint_value: @endpoint,
      polling_interval_value: @interval,
      polling_max_polls_value: @max_polls,
      polling_stop_condition_value: @stop_condition
    }
  end

  def host_aria
    @indicate_busy ? { busy: "true" } : {}
  end

  def content_data
    @content_target ? { polling_target: "content" } : {}
  end
end
