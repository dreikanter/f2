module Admin
  # Operator-facing variant of EventEntityPaths: entities with admin pages
  # point there; the rest keep their owner-facing pages.
  class EventEntityPaths < ::EventEntityPaths
    private

    def routes
      super.merge(
        "Feed" => :admin_feed_path,
        "User" => :admin_user_path,
        "Event" => :admin_event_path
      )
    end
  end
end
