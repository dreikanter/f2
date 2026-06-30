# Shared rendering helpers for the user-facing and admin event log entries.
# The two components keep separate templates because they present different
# information (the admin log also shows which user an event belongs to).
module EventLogEntryPresentation
  private

  # Every entry carries a severity icon. Warnings and errors stand out in
  # amber and red; routine events get a muted info circle so the column reads
  # as a continuous gutter.
  def severity_icon
    name, color = case event.level
    when "warning" then ["triangle-alert", "text-warning"]
    when "error" then ["circle-x", "text-danger"]
    else ["info", "text-muted"]
    end

    helpers.icon(name, css_class: "size-4 #{color}", aria_label: event.level.capitalize)
  end
end
