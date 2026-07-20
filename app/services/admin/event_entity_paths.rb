module Admin
  # Operator-facing variant of EventEntityPaths: entities with admin pages
  # point there; the rest keep their owner-facing pages.
  class EventEntityPaths < ::EventEntityPaths
    private

    def routes
      super.merge(
        "Feed" => :admin_feed_path,
        "User" => :admin_user_path,
        "Event" => :admin_event_path,
        "AccessToken" => :admin_access_token_path,
        "AiCredential" => :admin_ai_credential_path,
        "SearchCredential" => :admin_search_credential_path
      )
    end
  end
end
