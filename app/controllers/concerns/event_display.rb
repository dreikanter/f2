# The single-event page: what the event references, and where it sits in the
# log. Including controllers supply `navigable_events`, the scope the previous
# and next links walk.
module EventDisplay
  extend ActiveSupport::Concern

  MAX_REFERENCED_POSTS = 10

  private

  def load_event(event)
    @event = event
    @referenced_posts = referenced_posts(event).limit(MAX_REFERENCED_POSTS)
    @referenced_llm_usages = referenced_llm_usages(event)
    @referenced_web_searches = referenced_web_searches(event)
    @previous_event = adjacent_event(:older)
    @next_event = adjacent_event(:newer)
  end

  # Posts imported by the event, newest first, with feeds preloaded for cards.
  def referenced_posts(event)
    Post.where(id: event.event_references.where(reference_type: "Post").select(:reference_id))
        .includes(:feed)
        .order(created_at: :desc)
  end

  def referenced_llm_usages(event)
    LlmUsageReport.for_event(event).usages.includes(:message).chronological
  end

  def referenced_web_searches(event)
    WebSearchUsage.referenced_by(event)
  end

  # Follows the natural timeline direction: "previous" is the next-older
  # event, "next" is the next-newer one.
  def adjacent_event(direction)
    if direction == :newer
      navigable_events.where(cursor_condition(">", @event.id)).order(created_at: :asc, id: :asc).first
    else
      navigable_events.where(cursor_condition("<", @event.id)).order(created_at: :desc, id: :desc).first
    end
  end
end
