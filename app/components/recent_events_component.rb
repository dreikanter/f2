class RecentEventsComponent < ViewComponent::Base
  def initialize(events:)
    @events = events
  end

  def call
    return unless @events.any?

    render(list_component)
  end

  private

  attr_reader :events

  def list_component
    ListGroupComponent.new.tap do |list|
      list.with_items(@events.map { |event| event_item(event) })
    end
  end

  def event_item(event)
    ListGroupComponent::StatItemComponent.new(
      label: event_label(event),
      value: helpers.time_ago_tag(event.created_at),
      key: "recent_events.#{event.id}"
    )
  end

  def event_label(event)
    if event.message.present?
      event.message
    else
      fallback_message(event)
    end
  end

  def fallback_message(event)
    case event.type
    when "feed_refresh"
      "Feed refreshed"
    when "feed_refresh_error"
      "Feed refresh failed"
    when "post_withdrawn"
      "Post withdrawn"
    else
      event.type.humanize
    end
  end
end
