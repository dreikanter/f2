class Admin::EventsController < ApplicationController
  include Pagination
  include EventFiltering

  class_attribute :initial_events_limit, default: 20
  class_attribute :stream_events_limit, default: 100

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

  def events_for_log
    scope = events_scope.includes(:user, :subject)

    if request.format.turbo_stream? && next_event_window?
      scope.where("events.id > ?", after_id).order(id: :asc).limit(100).to_a.reverse
    else
      scope.order(id: :desc).limit(events_limit)
    end
  end

  def next_event_window?
    params[:force].blank? && after_id.positive? && events_scope.where("events.id > ?", after_id).limit(stream_events_limit + 1).count > stream_events_limit
  end

  def after_id
    params[:after_id].to_i
  end

  def events_limit
    request.format.turbo_stream? ? stream_events_limit : initial_events_limit
  end

  def render_events_stream
    return head :ok unless params[:force].present? || new_events?

    render turbo_stream: turbo_stream.replace(
      "admin_events_log",
      helpers.render(EventLogComponent.new(
        events: @events,
        endpoint: admin_events_path(format: :turbo_stream, filter: @filter.to_h.presence),
        path_builder: ->(event) { admin_event_path(event) },
        dom_id: "admin_events_log",
        admin: true
      ))
    )
  end

  def new_events?
    after_id < events_scope.maximum(:id).to_i
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
