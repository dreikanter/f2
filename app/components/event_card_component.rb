class EventCardComponent < ViewComponent::Base
  include EventLogEntryPresentation

  # Warning and error cards lean on the alert palette so problems stand out while
  # scanning the log; routine events stay neutral. The border picks a slightly
  # darker shade of the background hue, like AlertComponent does. Warning stays
  # gentle, so its border darkens on hover too — otherwise the hover background
  # would catch up to a static border and the two would read as one flat block.
  LEVEL_TINTS = {
    "warning" => { border: "border-amber-100", hover_border: "hover:border-amber-200", background: "bg-amber-50 hover:bg-amber-100" },
    "error" => { border: "border-red-200", background: "bg-red-100 hover:bg-red-200" }
  }.freeze

  DEFAULT_TINT = { border: "border-slate-200", background: "bg-white hover:bg-slate-50" }.freeze

  # `:simplified` shows just the severity, description and timestamp (status and
  # feed pages). `:extended` adds a footer with the event type, user and target
  # for the admin log.
  def initialize(event:, href:, mode: :simplified)
    @event = event
    @href = href
    @mode = mode
  end

  private

  attr_reader :event, :href, :mode

  def extended?
    mode == :extended
  end

  def card_classes
    helpers.class_names("w-full rounded-lg border shadow-xs transition duration-75", tint[:border], tint[:hover_border], tint[:background])
  end

  def divider_border
    tint[:border]
  end

  def tint
    LEVEL_TINTS.fetch(event.level, DEFAULT_TINT)
  end

  # In the admin log the severity icon doubles as a drill-down: clicking it
  # narrows the log to events of the same level. Elsewhere it is a plain marker.
  def severity
    return severity_marker unless extended?

    helpers.link_to(severity_icon,
                    helpers.admin_events_path(filter: { level: event.level }),
                    class: "flex w-4 shrink-0 items-center justify-center",
                    title: "Show #{event.level} events",
                    data: { key: "events.severity" })
  end

  def severity_marker
    helpers.content_tag(:span, severity_icon,
                        class: "flex w-4 shrink-0 items-center justify-center",
                        data: { key: "events.severity" })
  end

  def timestamp_link
    helpers.link_to(helpers.short_time_ago(event.created_at), href,
                    class: "shrink-0 text-sm font-medium tabular-nums text-slate-400 transition hover:text-slate-700",
                    title: event.created_at.rfc3339,
                    data: { key: "events.timestamp" })
  end

  def footer_items
    [type_link, user_label, target_label].compact
  end

  def type_link
    helpers.link_to(event.type,
                    helpers.admin_events_path(filter: { type: [event.type] }),
                    class: "font-mono transition hover:text-slate-700",
                    data: { key: "events.type" })
  end

  # Admins see who an event belongs to; the user links to a filtered log.
  def user_label
    label = if event.user_id.blank?
      helpers.tag.em("System", data: { key: "events.user" })
    else
      helpers.link_to("##{event.user_id}",
                      helpers.admin_events_path(filter: { user_id: event.user_id }),
                      class: "underline underline-offset-2 transition hover:text-slate-700",
                      title: event.user&.email_address,
                      data: { key: "events.user" })
    end

    safe_join(["User: ", label])
  end

  def target_label
    return if event.subject_type.blank?

    value = [event.subject_type, event.subject_id].compact.join("#")
    filter_params = { subject_type: event.subject_type }
    filter_params[:subject_id] = event.subject_id if event.subject_id.present?

    link = helpers.link_to(value,
                           helpers.admin_events_path(filter: filter_params),
                           class: "underline underline-offset-2 transition hover:text-slate-700",
                           title: target_title,
                           data: { key: "events.subject" })

    safe_join(["Target: ", link])
  end

  # Resolves the subject to its human name so admins don't have to memorize
  # ids; deleted subjects render without a hint.
  def target_title
    subject = event.subject
    return unless subject

    subject.try(:display_name) || subject.try(:name) || subject.try(:email_address)
  end
end
