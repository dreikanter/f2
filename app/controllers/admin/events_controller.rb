class Admin::EventsController < ApplicationController
  include Pagination
  include EventFiltering
  include EventStreaming

  class_attribute :initial_events_limit, default: 20

  def index
    authorize Event

    @filter = optional_filter
    @events = events_for_log

    respond_to do |format|
      format.html
      format.turbo_stream { render_events_stream }
    end
  end

  def show
    authorize Event
    @event = Event.find(params[:id])
    @previous_event = previous_event(@event)
    @next_event = next_event(@event)
  end

  private

  def pagination_scope
    events_scope.order(created_at: :desc)
  end

  def events_log_limit
    streaming? ? stream_events_limit : initial_events_limit
  end

  def event_log_dom_id
    "admin_events_log"
  end

  def event_log_component
    EventLogComponent.new(
      events: @events,
      endpoint: admin_events_path(format: :turbo_stream, filter: optional_filter.to_h.presence),
      path_builder: ->(event) { admin_event_path(event) },
      dom_id: event_log_dom_id,
      admin: true
    )
  end

  def previous_event(event)
    events_scope.where("id > ?", event.id).order(id: :asc).first
  end

  def next_event(event)
    events_scope.where("id < ?", event.id).order(id: :desc).first
  end

  def events_scope
    apply_filters(policy_scope(Event))
  end

  def permitted_filter_keys
    super + [:user_id]
  end
end
