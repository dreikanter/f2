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

  def compact_time_ago(time)
    short_time_ago(time)
  end
end
