class Admin::EventLogEntryComponent < ViewComponent::Base
  include EventLogEntryPresentation

  def initialize(event:, href:)
    @event = event
    @href = href
  end

  private

  attr_reader :event, :href

  # Admins see who an event belongs to; the user links to a filtered log.
  def user_label
    return helpers.tag.em("System", data: { key: "events.user" }) if event.user_id.blank?

    helpers.link_to(
      "User ##{event.user_id}",
      helpers.admin_events_path(filter: { user_id: event.user_id }),
      class: "underline underline-offset-2 hover:text-slate-700",
      data: { key: "events.user" }
    )
  end
end
