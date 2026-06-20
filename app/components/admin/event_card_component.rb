module Admin
  # Admin variant of EventCardComponent for the operator log: links feeds and
  # events to the admin pages, adds the type/user/target footer, and turns the
  # severity icon into a level drill-down.
  class EventCardComponent < ::EventCardComponent
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
                      class: "flex w-4 shrink-0 items-center justify-center",
                      title: "Show #{event.level} events",
                      data: { key: "events.severity" })
    end
  end
end
