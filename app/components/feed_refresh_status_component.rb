class FeedRefreshStatusComponent < ViewComponent::Base
  attr_reader :status

  def initialize(status:)
    @status = status
  end

  private

  def polling_data
    return {} unless status.refreshing?

    {
      controller: "polling",
      polling_endpoint_value: helpers.feed_path(status.feed, format: :turbo_stream, refresh_after: status.cursor),
      polling_interval_value: 5_000,
      polling_initial_delay_value: 5_000,
      polling_max_polls_value: 60,
      polling_indicate_busy_value: false,
      last_event_id: status.event&.id
    }
  end
end
