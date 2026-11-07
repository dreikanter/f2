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
    Event.where(user: Current.user).where.not(level: :debug).not_expired
  end

  alias_method :related_events_scope, :owned_events

  # The user's own log, unfiltered: the previous and next links walk the whole
  # timeline rather than whatever the index was last narrowed to.
  def navigable_events
    owned_events.user_relevant
  end

  def events_scope
    apply_filters(navigable_events)
  end

  def events_log_path(**params)
    events_path(filter: optional_filter.to_h.presence, **params)
  end
end
