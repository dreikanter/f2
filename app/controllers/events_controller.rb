class EventsController < ApplicationController
  include EventFiltering
  include EventStreaming

  def index
    @events = events_for_log

    respond_to do |format|
      format.turbo_stream { render_events_stream }
      format.html { redirect_to status_path }
    end
  end

  def show
    @event = events_scope.find(params[:id])
  end

  private

  def events_scope
    apply_filters(Event.where(user: Current.user).user_relevant)
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
