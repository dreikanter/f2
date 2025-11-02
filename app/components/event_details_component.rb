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
    user_value = if @event.user
      @event.user.email_address
    else
      helpers.tag.em("System", class: "text-slate-500")
    end

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "User",
      value: user_value
    ))
  end

  def add_subject_item(component)
    subject_value = helpers.safe_join([
      subject_link || subject_fallback,
      " ",
      helpers.tag.span("##{@event.subject_id}", class: "text-slate-500")
    ])

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

    if @event.subject.present?
      case @event.subject_type
      when "Feed"
        return helpers.link_to(@event.subject_type, helpers.feed_path(@event.subject), class: "ff-link", data: { key: "admin.event.subject.type" })
      when "Post"
        return helpers.link_to(@event.subject_type, helpers.post_path(@event.subject), class: "ff-link", data: { key: "admin.event.subject.type" })
      when "User"
        return helpers.link_to(@event.subject_type, helpers.admin_user_path(@event.subject), class: "ff-link", data: { key: "admin.event.subject.type" })
      end
    end

    helpers.link_to(@event.subject_type,
                    helpers.admin_events_path(filter: { subject_type: @event.subject_type }),
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
