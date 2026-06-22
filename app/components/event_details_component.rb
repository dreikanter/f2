# Renders the detail list shown at the top of an event page. Admin: true adds
# operator-only rows (user, timestamps, expiry).
class EventDetailsComponent < ViewComponent::Base
  def self.for(event, admin: false)
    new(event: event, admin: admin)
  end

  def initialize(event:, admin: false)
    @event = event
    @admin = admin
  end

  def call
    render(ListComponent.new) do |list|
      add_user_item(list) if @admin
      add_created_item(list)
      add_updated_item(list) if @admin
      add_expires_item(list) if @admin && @event.expires_at.present?
    end
  end

  private

  def add_user_item(component)
    user_value = if @event.user_id.present?
      helpers.link_to("User ##{@event.user_id}",
                      helpers.admin_events_path(filter: { user_id: @event.user_id }),
                      class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500",
                      data: { key: "admin.event.user" })
    else
      helpers.tag.em("System", class: "text-slate-500", data: { key: "admin.event.user" })
    end

    component.with_item(StatListItemComponent.new(
      label: "User",
      value: user_value
    ))
  end

  def add_created_item(component)
    value = helpers.safe_join([
      helpers.long_time_tag(@event.created_at),
      " ",
      helpers.tag.span("(#{helpers.short_time_ago(@event.created_at)})", class: "text-slate-500")
    ])

    component.with_item(StatListItemComponent.new(
      label: "Created",
      value: value
    ))
  end

  def add_updated_item(component)
    value = helpers.safe_join([
      helpers.long_time_tag(@event.updated_at),
      " ",
      helpers.tag.span("(#{helpers.short_time_ago(@event.updated_at)})", class: "text-slate-500")
    ])

    component.with_item(StatListItemComponent.new(
      label: "Updated",
      value: value
    ))
  end

  def add_expires_item(component)
    expires_value = helpers.safe_join([
      helpers.long_time_tag(@event.expires_at),
      " ",
      expires_status_badge
    ])

    component.with_item(StatListItemComponent.new(
      label: "Expires",
      value: expires_value
    ))
  end

  def expires_status_badge
    if @event.expired?
      helpers.tag.span("Expired", class: "inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/20")
    else
      helpers.tag.span("(in #{helpers.short_time_ago(@event.expires_at)})", class: "text-slate-500")
    end
  end
end
