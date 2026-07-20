module EventsHelper
  include IdentifierHelper

  # Explains where the current page sits in the log without leaning on page
  # numbers: the offset is how many newer events come before what's shown.
  def events_offset_summary(offset, system_wide: false)
    if offset.zero?
      system_wide ? "Showing system-wide most recent events." : "Showing the most recent events."
    else
      "#{pluralize(offset, 'newer event')} above what's shown here."
    end
  end

  # Describes the active events filter as entity references — "Feed [ce23f]",
  # with the id linked when `entity_paths` resolves a page for the entity —
  # plus plain `key: value` parts for the remaining filter keys.
  def event_filter_summary(filter, entity_paths:)
    filter = filter.to_h.stringify_keys
    parts = []

    if filter.values_at("subject_type", "subject_id").any?(&:present?)
      parts << event_entity_reference(filter["subject_type"], filter["subject_id"], entity_paths)
    end

    parts << event_entity_reference("User", filter["user_id"], entity_paths) if filter["user_id"].present?

    filter.except("subject_type", "subject_id", "user_id").each do |key, value|
      parts << "#{key}: #{Array.wrap(value).join(', ')}"
    end

    safe_join(parts, " • ")
  end

  def admin_event_subject_path(subject)
    subject && Admin::EventEntityPaths.new.path_for(subject.class.name, subject.id)
  end

  def format_stat_value(key, value)
    key = key.to_s

    if key.end_with?("_at")
      time = Time.zone.parse(value.to_s) rescue nil
      time ? long_time_tag(time) : value
    elsif key.end_with?("_duration")
      format_event_duration(value.to_f)
    elsif key.end_with?("_cents")
      number_to_currency(value.to_f / 100.0)
    elsif value.is_a?(Integer)
      number_with_delimiter(value)
    else
      value
    end
  end

  def format_event_duration(seconds)
    return "#{seconds.round(1)}s" if seconds < 60

    minutes = (seconds / 60).floor
    remaining = (seconds % 60).round
    "#{minutes}m #{remaining}s"
  end

  def mail_event_types
    ResendWebhooksController::EMAIL_EVENT_HANDLERS.values.pluck(:type) + %w[
      mail.profile_mailer.account_confirmation
      mail.profile_mailer.email_change_confirmation
      mail.passwords_mailer.reset
    ]
  end

  private

  # "Feed [ce23f]" — a humanized entity type with a short linked id. Either
  # half may be missing: a type-only filter renders just the label, an id
  # without a type gets a generic label and stays unlinked.
  def event_entity_reference(type, id, entity_paths)
    label = type.present? ? type.demodulize.underscore.humanize : "Subject"
    return tag.strong(label) if id.blank?

    path = type.present? ? entity_paths.path_for(type, id) : nil
    ref = if path
      link_to(
        short_ref(id),
        path,
        title: id,
        class: "font-mono underline underline-offset-2 transition hover:text-heading"
      )
    else
      tag.span(short_ref(id), title: id, class: "font-mono")
    end

    tag.strong(safe_join([label, " [", ref, "]"]))
  end
end
