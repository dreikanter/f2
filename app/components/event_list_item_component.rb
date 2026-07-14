class EventListItemComponent < ListItemComponent
  include EventLogEntryPresentation

  # Warning and error rows lean on the alert palette so problems stand out while
  # scanning the log; routine events stay neutral. Rows sit inside a single
  # bordered list, so only the background is tinted — separation comes from the
  # list's dividers rather than per-row borders.
  LEVEL_TINTS = {
    "warning" => "bg-warning-subtle hover:bg-warning-subtle",
    "error" => "bg-danger-subtle hover:bg-danger-subtle"
  }.freeze

  DEFAULT_TINT = "bg-surface hover:bg-surface-muted".freeze

  # Shows the severity, description and timestamp. Admin::EventListItemComponent
  # adds a footer with the event type, user and target for the operator log.
  def initialize(event:, href:)
    super()
    @event = event
    @href = href
  end

  def before_render
    with_icon { severity }
    with_primary { primary_element }
    with_secondary { footer } if show_footer?
  end

  private

  attr_reader :event, :href

  def li_data
    {
      key: "events.entry",
      event_type: event.type,
      event_id: event.id
    }
  end

  def row_css_class
    helpers.class_names("transition duration-75", tint)
  end

  def primary_element
    helpers.tag.div(
      helpers.safe_join([
        helpers.tag.div(render(description), class: "min-w-0 flex-1 truncate text-heading", data: { key: "events.description" }),
        timestamp_link
      ]),
      class: "flex min-w-0 flex-1 items-baseline gap-3"
    )
  end

  def footer
    helpers.tag.div(helpers.safe_join(footer_items, helpers.middot),
                    class: "truncate text-sm text-muted", data: { key: "events.footer" })
  end

  def description
    description_component_class.for(event)
  end

  def description_component_class
    EventDescriptionComponent
  end

  # Whether to render the footer (type/user/target). Admin::EventListItemComponent
  # enables it for the operator log.
  def show_footer?
    false
  end

  def tint
    LEVEL_TINTS.fetch(event.level, DEFAULT_TINT)
  end

  # A plain marker by default. Admin::EventListItemComponent turns it into a
  # drill-down link that narrows the log to events of the same level. The icon
  # sits in the first row and is centered with it by the row's items-center.
  def severity
    helpers.content_tag(:span, severity_icon,
                        class: "inline-flex shrink-0",
                        data: { key: "events.severity" })
  end

  def timestamp_link
    helpers.link_to(helpers.short_time_ago(event.created_at), href,
                    class: "shrink-0 text-sm font-medium tabular-nums text-muted transition hover:text-heading",
                    title: event.created_at.rfc3339,
                    data: { key: "events.timestamp" })
  end

  def footer_items
    [type_link, user_label, target_label].compact
  end

  def type_link
    link = helpers.link_to(event.type,
                           helpers.admin_events_path(filter: { type: [event.type] }),
                           class: "transition hover:text-heading",
                           data: { key: "events.type" })

    safe_join(["Type: ", link])
  end

  # Admins see who an event belongs to; existing users link to their detail page.
  def user_label
    label = if event.user_id.blank?
      helpers.tag.em("System", data: { key: "events.user" })
    else
      helpers.uuid_reference(
        event.user_id,
        path: (helpers.admin_user_path(event.user) if event.user),
        title: reference_title(event.user_id, event.user&.email_address),
        data: { key: "events.user" }
      )
    end

    safe_join(["User: ", label])
  end

  def target_label
    return if event.subject_type.blank?

    label = if event.subject_id.present?
      helpers.uuid_reference(
        event.subject_id,
        path: helpers.admin_event_subject_path(event.subject),
        prefix: event.subject_type,
        title: reference_title(event.subject_id, target_title),
        data: { key: "events.subject" }
      )
    else
      helpers.tag.span(event.subject_type, data: { key: "events.subject" })
    end

    safe_join(["Target: ", label])
  end

  # Resolves the subject to its human name so admins don't have to memorize
  # ids; deleted subjects render without a hint.
  def target_title
    subject = event.subject
    return unless subject

    subject.try(:display_name) || subject.try(:name) || subject.try(:email_address)
  end

  def reference_title(id, description)
    [id, description].compact_blank.join(" — ")
  end
end
