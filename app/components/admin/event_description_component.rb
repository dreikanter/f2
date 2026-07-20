module Admin
  # Admin variant of EventDescriptionComponent: identical rendering, but
  # entity references point at the operator-facing pages. Reuses the base type
  # resolution and mixes the admin link behavior into whichever subclass it
  # returns, so new event-type subclasses are covered automatically.
  class EventDescriptionComponent < ::EventDescriptionComponent
    def self.for(event)
      ::EventDescriptionComponent.for(event).extend(EventEntityLinks)
    end
  end
end
