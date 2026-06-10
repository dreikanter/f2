class Admin::EventLogEntryComponent < ViewComponent::Base
  include EventLogEntryPresentation

  # Warning and error cards reuse the alert palette so problems stand out
  # while scanning the log; routine events stay neutral. The border picks a
  # slightly darker shade of the background hue, like AlertComponent does.
  LEVEL_TINTS = {
    "warning" => { border: "border-amber-200", background: "bg-amber-100 hover:bg-amber-200" },
    "error" => { border: "border-red-200", background: "bg-red-100 hover:bg-red-200" }
  }.freeze

  DEFAULT_TINT = { border: "border-slate-200", background: "bg-white hover:bg-slate-50" }.freeze

  def initialize(event:, href:)
    @event = event
    @href = href
  end

  private

  attr_reader :event, :href

  def card_classes
    helpers.class_names("w-full rounded-lg border shadow-xs transition duration-75", tint[:border], tint[:background])
  end

  def divider_border
    tint[:border]
  end

  def tint
    LEVEL_TINTS.fetch(event.level, DEFAULT_TINT)
  end

  # The severity gutter doubles as a drill-down: clicking the icon narrows
  # the log to events of the same level.
  def severity_link
    helpers.link_to(severity_icon,
                    helpers.admin_events_path(filter: { level: event.level }),
                    class: "flex w-4 shrink-0 items-center justify-center",
                    title: "Show #{event.level} events",
                    data: { key: "events.severity" })
  end

  # The timestamp sits leftmost so it survives the narrow-screen truncation;
  # everything after it clips with an ellipsis.
  def footer_items
    [timestamp_link, type_link, user_label, target_label].compact
  end

  def timestamp_link
    helpers.link_to(helpers.short_time_ago(event.created_at), href,
                    class: "font-medium transition hover:text-slate-700",
                    title: event.created_at.rfc3339,
                    data: { key: "events.timestamp" })
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
