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

  def event_log_dom_id
    "user_events_log"
  end

  def event_log_component
    EventLogComponent.new(
      events: @events,
      endpoint: events_path(format: :turbo_stream, filter: optional_filter.to_h.presence),
      path_builder: ->(event) { event_path(event) },
      dom_id: event_log_dom_id
    )
  end
end
