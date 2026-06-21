module Admin
  # Admin variant of EventListItemComponent for the operator log: links feeds and
  # events to the admin pages, adds the type/user/target footer, and turns the
  # severity icon into a level drill-down.
  class EventListItemComponent < ::EventListItemComponent
    private

    def description_component_class
      Admin::EventDescriptionComponent
    end

    def show_footer?
      true
    end

    def severity
      helpers.link_to(severity_icon,
                      helpers.admin_events_path(filter: { level: event.level }),
                      class: "inline-flex shrink-0",
                      title: "Show #{event.level} events",
                      data: { key: "events.severity" })
    end
  end
end
