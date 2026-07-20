# Renders the detail list shown at the top of an event page: base event
# attributes followed by any stats captured in the event metadata. Admin: true
# adds operator-only rows (user, timestamps, expiry). Subclasses can override
# #items (or any individual row method) to reshape the list for specific
# event presentations.
class EventDetailsComponent < ViewComponent::Base
  # Search calls are surfaced by the dedicated search usage section, so the
  # details list skips them to avoid showing the same number twice.
  HIDDEN_STATS = %w[search_calls].freeze

  def initialize(event:, admin: false)
    @event = event
    @admin = admin
  end

  def call
    render(ListComponent.new) do |list|
      items.each { |item| list.with_item(item) }
    end
  end

  private

  # Ordered rows of the details list.
  def items
    [
      (user_item if @admin),
      created_item,
      (updated_item if @admin),
      (expires_item if @admin && @event.expires_at.present?),
      *stat_items
    ].compact
  end

  def user_item
    user_value = if @event.user_id.present?
      title = [@event.user_id, @event.user&.email_address].compact_blank.join(" — ")

      if @event.user
        helpers.link_to(
          helpers.short_ref(@event.user_id),
          helpers.admin_user_path(@event.user),
          title: title,
          class: "font-mono font-medium text-brand underline underline-offset-4 transition hover:text-brand-hover",
          data: { key: "admin.event.user" }
        )
      else
        helpers.tag.span(
          helpers.short_ref(@event.user_id),
          title: title,
          class: "font-mono font-medium text-body",
          data: { key: "admin.event.user" }
        )
      end
    else
      helpers.tag.em("System", class: "text-muted", data: { key: "admin.event.user" })
    end

    StatListItemComponent.new(
      label: "User",
      value: user_value
    )
  end

  def created_item
    StatListItemComponent.new(
      label: "Created",
      value: helpers.datetime_with_duration_tag(@event.created_at)
    )
  end

  def updated_item
    StatListItemComponent.new(
      label: "Updated",
      value: helpers.datetime_with_duration_tag(@event.updated_at)
    )
  end

  def expires_item
    expires_value = helpers.safe_join([
      helpers.long_time_tag(@event.expires_at),
      " ",
      expires_status_badge
    ])

    StatListItemComponent.new(
      label: "Expires",
      value: expires_value
    )
  end

  def expires_status_badge
    if @event.expired?
      render(BadgeComponent.new(text: "Expired", color: :danger))
    else
      helpers.tag.span("(in #{helpers.short_time_ago(@event.expires_at)})", class: "text-muted")
    end
  end

  def stat_items
    stats.map do |key, value|
      StatListItemComponent.new(
        label: helpers.t("events.metadata.stats.#{key}", default: key.humanize),
        value: helpers.format_stat_value(key, value),
        key: "events.stats.#{key}"
      )
    end
  end

  def stats
    @event.metadata&.fetch("stats", nil).to_h.except(*HIDDEN_STATS)
  end
end
