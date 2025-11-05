class EventDetailsComponent < ViewComponent::Base
  def initialize(event:)
    @event = event
  end

  def call
    component = ListGroupComponent.new

    add_type_item(component)
    add_level_item(component)
    add_user_item(component)
    add_subject_item(component)
    add_created_item(component)
    add_updated_item(component)
    add_expires_item(component) if @event.expires_at.present?

    render(component)
  end

  private

  def add_type_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Type",
      value: helpers.tag.code(@event.type, class: "text-sm", data: { key: "admin.events.type" })
    ))
  end

  def add_level_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Level",
      value: @event.level.capitalize
    ))
  end

  def add_user_item(component)
    user_value = if @event.user_id.present?
      helpers.link_to("User ##{@event.user_id}",
                      helpers.admin_events_path(filter: { user_id: @event.user_id }),
                      class: "ff-link",
                      data: { key: "admin.event.user" })
    else
      helpers.tag.em("System", class: "text-slate-500", data: { key: "admin.event.user" })
    end

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "User",
      value: user_value
    ))
  end

  def add_subject_item(component)
    parts = [subject_link || subject_fallback]

    if @event.subject_id.present?
      parts << " "
      parts << helpers.tag.span("##{@event.subject_id}", class: "text-slate-500")
    end

    subject_value = helpers.safe_join(parts)

    component.with_item(ListGroupComponent::StatItemComponent.new(
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

    component.with_item(ListGroupComponent::StatItemComponent.new(
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

    component.with_item(ListGroupComponent::StatItemComponent.new(
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

    component.with_item(ListGroupComponent::StatItemComponent.new(
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
                    class: "ff-link",
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
