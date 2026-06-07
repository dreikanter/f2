class EventsController < ApplicationController
  include EventFiltering
  include EventCursorPagination
  include EventReferencedPosts

  def index
    respond_to do |format|
      format.html { render_events_page }
      format.turbo_stream { render_events_stream }
    end
  end

  def show
    @event = owned_events.find(params[:id])
    @referenced_posts = referenced_posts(@event)
    @previous_event = adjacent_event(:newer)
    @next_event = adjacent_event(:older)
  end

  private

  def owned_events
    Event.where(user: Current.user).user_relevant
  end

  # Navigates the user's own log in the same chronological order as the list:
  # "previous" is the next-newer event, "next" is the next-older one.
  def adjacent_event(direction)
    if direction == :newer
      owned_events.where(cursor_condition(">", @event.id)).order(created_at: :asc, id: :asc).first
    else
      owned_events.where(cursor_condition("<", @event.id)).order(created_at: :desc, id: :desc).first
    end
  end

  def events_scope
    apply_filters(owned_events)
  end

  def events_log_path(**params)
    events_path(filter: optional_filter.to_h.presence, **params)
  end
end
