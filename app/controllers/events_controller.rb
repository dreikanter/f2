class EventsController < ApplicationController
  include EventFiltering
  include EventCursorPagination

  def index
    respond_to do |format|
      format.html { render_events_page }
      format.turbo_stream { render_events_stream }
    end
  end

  def show
    @event = owned_events.find(params[:id])
  end

  private

  def owned_events
    Event.where(user: Current.user).user_relevant
  end

  def events_scope
    apply_filters(owned_events)
  end

  def entry_component(event)
    EventLogEntryComponent.new(event: event, href: event_path(event))
  end

  def events_log_path(**params)
    events_path(filter: optional_filter.to_h.presence, **params)
  end
end
