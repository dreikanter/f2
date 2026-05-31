class EventsController < ApplicationController
  include EventFiltering
  include EventStreaming

  def index
    respond_to do |format|
      format.turbo_stream { render_events_stream }
      format.html { redirect_to status_path }
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

  def event_log_component
    EventLogComponent.new(
      events: @events,
      endpoint: events_path(format: :turbo_stream, filter: optional_filter.to_h.presence)
    )
  end

  def entry_component(event)
    EventLogEntryComponent.new(event: event, href: event_path(event))
  end
end
