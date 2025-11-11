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
    description = EventDescriptionRenderer.new(event).render

    helpers.safe_join([
      helpers.render(BadgeComponent.new(text: event.level.humanize, color: badge_color(event.level))),
      " ",
      description
    ])
  end

  def badge_color(level)
    case level
    when "debug"
      :gray
    when "info"
      :blue
    when "warning"
      :yellow
    when "error"
      :red
    else
      :blue
    end
  end
end
