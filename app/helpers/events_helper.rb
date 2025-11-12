module EventsHelper
  LEVEL_BADGES = {
    "debug" => { class: "badge bg-secondary", char: "D" },
    "info" => { class: "badge bg-primary", char: "I" },
    "warning" => { class: "badge bg-warning", char: "W" },
    "error" => { class: "badge bg-danger", char: "E" }
  }.freeze

  LEVEL_ALERT_CLASSES = {
    "error" => "ff-alert ff-alert--error",
    "warning" => "ff-alert ff-alert--warning"
  }.freeze

  def level_badge(level)
    badge = LEVEL_BADGES.fetch(level.to_s, LEVEL_BADGES["debug"])
    content_tag(:span, badge[:char], class: "#{badge[:class]} font-monospace", title: level.humanize)
  end

  def level_badge_full(level)
    badge = LEVEL_BADGES.fetch(level.to_s, LEVEL_BADGES["debug"])
    content_tag(:span, level.humanize, class: badge[:class])
  end

  def event_alert_class(level)
    LEVEL_ALERT_CLASSES.fetch(level.to_s, "ff-alert ff-alert--info")
  end

  def mail_event_types
    ResendWebhooksController::EMAIL_EVENT_HANDLERS.values.pluck(:type) + %w[
      mail.profile_mailer.account_confirmation
      mail.profile_mailer.email_change_confirmation
      mail.passwords_mailer.reset
    ]
  end
end
