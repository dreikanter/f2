class EventsController < ApplicationController
  include EventFiltering
  include EventCursorPagination
  include EventDisplay

  def index
    @filter = optional_filter

    respond_to do |format|
      format.html { render_events_page }
      format.turbo_stream { render_events_stream }
    end
  end

  def show
    load_event(owned_events.find(params[:id]))
  end

  private

  def owned_events
    Event.where(user: Current.user).user_relevant
  end

  # The user's own log, unfiltered: the previous and next links walk the whole
  # timeline rather than whatever the index was last narrowed to.
  alias_method :navigable_events, :owned_events

  def events_scope
    apply_filters(owned_events)
  end

  def events_log_path(**params)
    events_path(filter: optional_filter.to_h.presence, **params)
  end
end
