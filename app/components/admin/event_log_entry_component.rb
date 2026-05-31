class Admin::EventLogEntryComponent < EventLogEntryComponent
  private

  # Admins always see who an event belongs to, including system events.
  def show_user_label?
    true
  end

  # The user becomes a link that filters the admin events log.
  def user_label
    return super if event.user_id.blank?

    helpers.link_to(
      "User ##{event.user_id}",
      helpers.admin_events_path(filter: { user_id: event.user_id }),
      class: "underline decoration-dotted underline-offset-2 hover:text-slate-700",
      data: { key: "events.user" }
    )
  end
end
