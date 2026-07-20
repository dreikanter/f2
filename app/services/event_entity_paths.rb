# Resolves the page that displays an entity referenced from the events log,
# given its class name and id. This base resolver targets the owner-facing
# pages; Admin::EventEntityPaths points entities with operator pages there
# instead. To make a new entity type linkable, add its route to `routes`.
class EventEntityPaths
  include Rails.application.routes.url_helpers

  # Returns the path for the entity, or nil when no page displays it.
  def path_for(type, id)
    route = routes[type.to_s]
    route && public_send(route, id)
  end

  private

  def routes
    {
      "Feed" => :feed_path,
      "Event" => :event_path,
      "Post" => :post_path,
      "AccessToken" => :access_token_path,
      "AiCredential" => :ai_credential_path,
      "SearchCredential" => :search_credential_path
    }
  end
end
