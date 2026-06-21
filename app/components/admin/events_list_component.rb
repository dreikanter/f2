module Admin
  # Admin variant of EventsListComponent: links each event to the operator-facing
  # event page and renders the richer Admin::EventListItemComponent rows. The
  # admin panel always shows the detailed two-row event with the type/user/target
  # footer.
  class EventsListComponent < ::EventsListComponent
    private

    def item_component(event)
      Admin::EventListItemComponent.new(event: event, href: event_href(event))
    end

    def event_href(event)
      helpers.admin_event_path(event)
    end
  end
end
