class EventsController < ApplicationController
  class_attribute :stream_events_limit, default: 100

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
    Event.where(user: Current.user).user_relevant
  end

  def events_for_log
    scope = events_scope.includes(:user, :subject)

    if next_event_window?
      scope.where("events.id > ?", after_id).order(id: :asc).limit(stream_events_limit).to_a.reverse
    else
      scope.order(id: :desc).limit(stream_events_limit)
    end
  end

  def next_event_window?
    params[:force].blank? && after_id.positive? && events_scope.where("events.id > ?", after_id).limit(stream_events_limit + 1).count > stream_events_limit
  end

  def after_id
    params[:after_id].to_i
  end

  def render_events_stream
    return head :ok unless params[:force].present? || new_events?

    render turbo_stream: turbo_stream.replace(
      "user_events_log",
      helpers.render(EventLogComponent.new(
        events: @events,
        endpoint: events_path(format: :turbo_stream),
        path_builder: ->(event) { event_path(event) },
        dom_id: "user_events_log"
      ))
    )
  end

  def new_events?
    after_id < events_scope.maximum(:id).to_i
  end
end
