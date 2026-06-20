module Admin
  # Admin variant of EventDescriptionComponent: identical rendering, but feed
  # references point at the operator-facing feed page. Reuses the base type
  # resolution and mixes the admin link behavior into whichever subclass it
  # returns, so new event-type subclasses are covered automatically.
  class EventDescriptionComponent < ::EventDescriptionComponent
    def self.for(event)
      ::EventDescriptionComponent.for(event).extend(FeedLinks)
    end
  end
end
