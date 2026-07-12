module EventsHelper
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
end
