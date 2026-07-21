# Shared rendering helpers for the user-facing and admin event log entries.
# The two components keep separate templates because they present different
# information (the admin log also shows which user an event belongs to).
module EventLogEntryPresentation
  private

  # Every entry carries a leading icon. Its shape comes from the per-type
  # configuration (EventIcons) when one exists, otherwise from the event's
  # level; the color always tracks the level so warnings and errors stand out
  # in amber and red while routine events stay muted.
  def severity_icon
    name = EventIcons.icon_for(event.type) || level_icon_name
    helpers.icon(name, css_class: "size-4 #{level_icon_color}", aria_label: event.level.capitalize)
  end

  def level_icon_name
    case event.level
    when "warning" then "triangle-alert"
    when "error" then "circle-x"
    else "info"
    end
  end

  def level_icon_color
    case event.level
    when "warning" then "text-warning"
    when "error" then "text-danger"
    else "text-muted"
    end
  end
end
