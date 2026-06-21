module Admin
  # The operator events log shown at /admin/events. Same bordered, polling,
  # cursor-paginated list as Admin::EventsListComponent, but renders the richer
  # Admin::EventListItemComponent rows (with the type/user/target footer).
  class EventsLogComponent < EventsListComponent
    private

    def item_component(event)
      Admin::EventListItemComponent.new(event: event, href: event_href(event))
    end
  end
end
