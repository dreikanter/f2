# Renders the detail list shown at the top of an event page. The base knows
# only how to present the fields common to every event; type-specific extras
# (e.g. feed refresh stats) live in subclasses picked by .for, mirroring
# EventDescriptionComponent. The base stays oblivious to concrete event types —
# the SUBCLASSES mapping is the single place that ties a type to a component.
#
# The same component serves the user-facing and admin pages; admin: true adds
# the operator-only rows (user, timestamps, expiry) and the admin filter links.
class EventDetailsComponent < ViewComponent::Base
  SUBCLASSES = {
    "feed_refresh" => "FeedRefreshDetailsComponent"
  }.freeze

  def self.for(event, admin: false)
    klass = SUBCLASSES[event.type]&.constantize || self
    klass.new(event: event, admin: admin)
  end

  def initialize(event:, admin: false)
    @event = event
    @admin = admin
  end

  def call
    render(ListComponent.new) do |list|
      add_type_item(list)
      add_level_item(list)
      add_user_item(list) if @admin
      add_subject_item(list)
      add_created_item(list)
      add_updated_item(list) if @admin
      add_expires_item(list) if @admin && @event.expires_at.present?
      extra_items(list)
    end
  end

  private

  # Extension point for subclasses to append type-specific rows. No-op here so
  # the base carries no knowledge of any particular event type.
  def extra_items(component)
  end

  def add_type_item(component)
    type_key = @admin ? "admin.events.type" : "events.type"

    component.with_item(ListComponent::StatItemComponent.new(
      label: "Type",
      value: helpers.tag.code(@event.type, class: "text-sm", data: { key: type_key })
    ))
  end

  def add_level_item(component)
    component.with_item(ListComponent::StatItemComponent.new(
      label: "Level",
      value: @event.level.capitalize
    ))
  end

  def add_user_item(component)
    user_value = if @event.user_id.present?
      helpers.link_to("User ##{@event.user_id}",
                      helpers.admin_events_path(filter: { user_id: @event.user_id }),
                      class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500",
                      data: { key: "admin.event.user" })
    else
      helpers.tag.em("System", class: "text-slate-500", data: { key: "admin.event.user" })
    end

    component.with_item(ListComponent::StatItemComponent.new(
      label: "User",
      value: user_value
    ))
  end

  def add_subject_item(component)
    if @admin
      add_admin_subject_item(component)
    else
      add_plain_subject_item(component)
    end
  end

  def add_admin_subject_item(component)
    parts = [subject_link || subject_fallback]

    if @event.subject_id.present?
      parts << " "
      parts << helpers.tag.span("##{@event.subject_id}", class: "text-slate-500")
    end

    component.with_item(ListComponent::StatItemComponent.new(
      label: "Subject",
      value: helpers.safe_join(parts)
    ))
  end

  def add_plain_subject_item(component)
    return unless @event.subject_type.present?

    subject_value = if @event.subject_id.present?
      "#{@event.subject_type} ##{@event.subject_id}"
    else
      @event.subject_type
    end

    component.with_item(ListComponent::StatItemComponent.new(
      label: "Subject",
      value: subject_value
    ))
  end

  def add_created_item(component)
    value = helpers.safe_join([
      helpers.long_time_tag(@event.created_at),
      " ",
      helpers.tag.span("(#{helpers.short_time_ago(@event.created_at)})", class: "text-slate-500")
    ])

    component.with_item(ListComponent::StatItemComponent.new(
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

    component.with_item(ListComponent::StatItemComponent.new(
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

    component.with_item(ListComponent::StatItemComponent.new(
      label: "Expires",
      value: expires_value
    ))
  end

  def subject_link
    return unless @event.subject_type.present?

    filter_params = { subject_type: @event.subject_type }
    filter_params[:subject_id] = @event.subject_id if @event.subject_id.present?

    helpers.link_to(@event.subject_type,
                    helpers.admin_events_path(filter: filter_params),
                    class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500",
                    data: { key: "admin.event.subject.type" })
  end

  def subject_fallback
    @event.subject_type.presence || helpers.tag.em("None", class: "text-slate-500")
  end

  def expires_status_badge
    if @event.expired?
      helpers.tag.span("Expired", class: "inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/20")
    else
      helpers.tag.span("(in #{helpers.short_time_ago(@event.expires_at)})", class: "text-slate-500")
    end
  end
end
