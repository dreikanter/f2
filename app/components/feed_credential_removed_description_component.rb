# Chooses wording based on whether credential removal also changed the feed's
# state. Draft and already-disabled feeds still get an activity event, without
# claiming they were disabled by the removal.
class FeedCredentialRemovedDescriptionComponent < EventDescriptionComponent
  private

  def description_key
    variant = event.metadata["disabled"] ? "disabled_description_html" : "description_html"
    "events.#{event_type}.#{variant}"
  end
end
