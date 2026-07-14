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

  def admin_event_filter_summary(filter)
    parts = filter.to_h.map do |key, value|
      values = Array.wrap(value).map do |item|
        admin_event_filter_value(key, item, filter:)
      end

      safe_join(["#{key}: ", safe_join(values, ", ")])
    end

    safe_join(parts, " • ")
  end

  def admin_event_subject_path(subject)
    case subject
    when Feed
      admin_feed_path(subject)
    when User
      admin_user_path(subject)
    when Event
      admin_event_path(subject)
    when AccessToken
      access_token_path(subject)
    when AiCredential
      ai_credential_path(subject)
    when SearchCredential
      search_credential_path(subject)
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

  private

  def admin_event_filter_value(key, value, filter:)
    return value unless %w[user_id subject_id].include?(key.to_s)

    path = admin_event_filter_reference_path(key, value, filter:)
    text = short_ref(value)

    if path
      link_to(
        text,
        path,
        title: value,
        class: "font-mono underline underline-offset-2 transition hover:text-heading"
      )
    else
      tag.span(text, title: value, class: "font-mono")
    end
  end

  def admin_event_filter_reference_path(key, value, filter:)
    case key.to_s
    when "user_id"
      admin_user_path(value)
    when "subject_id"
      case filter[:subject_type] || filter["subject_type"]
      when "Feed"
        admin_feed_path(value)
      when "User"
        admin_user_path(value)
      when "Event"
        admin_event_path(value)
      when "AccessToken"
        access_token_path(value)
      when "AiCredential"
        ai_credential_path(value)
      when "SearchCredential"
        search_credential_path(value)
      end
    end
  end
end
