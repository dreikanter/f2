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
    seconds = Time.current - time

    case seconds
    when 0..59
      "#{seconds.to_i}s"
    when 60..3599
      "#{(seconds / 60).to_i}m"
    when 3600..86399
      "#{(seconds / 3600).to_i}h"
    when 86400..2591999
      "#{(seconds / 86400).to_i}d"
    else
      "#{(seconds / 2592000).to_i}mo"
    end
  end
end
