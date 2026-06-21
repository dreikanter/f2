class Admin::EventsController < ApplicationController
  include EventFiltering
  include EventCursorPagination
  include EventReferencedPosts

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
    @referenced_posts = referenced_posts(@event)
    @previous_event = previous_event(@event)
    @next_event = next_event(@event)
  end

  private

  def events_log_path(**params)
    admin_events_path(filter: optional_filter.to_h.presence, **params)
  end

  # The admin log renders the richer Admin::EventListItemComponent rows; the
  # shared streaming defaults to the user-facing EventsListComponent.
  def events_log_stream_body
    helpers.render(Admin::EventsLogComponent.new(events: @events, endpoint: @log_endpoint, older_url: @older_url, newer_url: @newer_url))
  end

  def previous_event(event)
    events_scope.where("id < ?", event.id).order(id: :desc).first
  end

  def next_event(event)
    events_scope.where("id > ?", event.id).order(id: :asc).first
  end

  def events_scope
    apply_filters(policy_scope(Event))
  end

  def permitted_filter_keys
    super + [:user_id]
  end
end
