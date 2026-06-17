module EventsHelper
  LEVEL_BADGES = {
    "debug" => { class: "badge bg-secondary", char: "D" },
    "info" => { class: "badge bg-primary", char: "I" },
    "warning" => { class: "badge bg-warning", char: "W" },
    "error" => { class: "badge bg-danger", char: "E" }
  }.freeze

  def level_badge(level)
    badge = LEVEL_BADGES.fetch(level.to_s, LEVEL_BADGES["debug"])
    content_tag(:span, badge[:char], class: "#{badge[:class]} font-monospace", title: level.humanize)
  end

  def level_badge_full(level)
    badge = LEVEL_BADGES.fetch(level.to_s, LEVEL_BADGES["debug"])
    content_tag(:span, level.humanize, class: badge[:class])
  end

  # Explains where the current page sits in the log without leaning on page
  # numbers: the offset is how many newer events come before what's shown.
  def events_offset_summary(offset, system_wide: false)
    if offset.zero?
      system_wide ? "Showing system-wide most recent events." : "Showing the most recent events."
    else
      "#{pluralize(offset, 'newer event')} above what's shown here."
    end
  end

  def format_stat_value(key, value)
    if key.to_s.end_with?("_at")
      time = Time.zone.parse(value.to_s) rescue nil
      time ? long_time_tag(time) : value
    elsif key.to_s == "total_duration"
      format_event_duration(value.to_f)
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
end
