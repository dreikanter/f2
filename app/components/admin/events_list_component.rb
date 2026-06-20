module Admin
  # Admin variant of EventsListComponent: links each event to the
  # operator-facing event page instead of the user-facing one.
  class EventsListComponent < ::EventsListComponent
    private

    def event_href(event)
      helpers.admin_event_path(event)
    end
  end
end
