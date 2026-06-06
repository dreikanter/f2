class Admin::EventsController < ApplicationController
  include EventFiltering
  include EventCursorPagination

  def index
    authorize Event

    @filter = optional_filter

    respond_to do |format|
      format.html { render_events_page }
      format.turbo_stream { render_events_stream }
    end
  end

  def show
    authorize Event
    @event = Event.find(params[:id])
    @referenced_posts = Post.where(id: @event.event_references.where(reference_type: "Post").select(:reference_id))
                            .includes(:feed)
                            .order(created_at: :desc)
    @previous_event = previous_event(@event)
    @next_event = next_event(@event)
  end

  private

  def entry_component(event)
    Admin::EventLogEntryComponent.new(event: event, href: admin_event_path(event))
  end

  def events_log_path(**params)
    admin_events_path(filter: optional_filter.to_h.presence, **params)
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
