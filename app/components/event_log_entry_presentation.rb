# Shared rendering helpers for the user-facing and admin event log entries.
# The two components keep separate templates because they present different
# information (the admin log also shows which user an event belongs to).
module EventLogEntryPresentation
  private

  def badge_color(level)
    case level
    when "debug" then :gray
    when "info" then :blue
    when "warning" then :yellow
    when "error" then :red
    else :blue
    end
  end

  def subject_label
    return if event.subject_type.blank?

    value = event.subject_id.present? ? "#{event.subject_type} ##{event.subject_id}" : event.subject_type

    filter_params = { subject_type: event.subject_type }
    filter_params[:subject_id] = event.subject_id if event.subject_id.present?

    helpers.link_to(
      value,
      subject_filter_path(filter_params),
      class: "underline underline-offset-2 hover:text-slate-700",
      data: { key: "events.subject" }
    )
  end

  def subject_filter_path(filter_params)
    helpers.events_path(filter: filter_params)
  end
end
