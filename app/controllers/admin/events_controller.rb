class Admin::EventsController < ApplicationController
  include EventFiltering
  include EventCursorPagination
  include EventDisplay

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
    load_event(Event.find(params[:id]))
  end

  private

  def event_entity_paths
    Admin::EventEntityPaths.new
  end

  def events_log_path(**params)
    admin_events_path(filter: optional_filter.to_h.presence, **params)
  end

  # The admin log renders the richer Admin::EventListItemComponent rows; the
  # shared streaming defaults to the user-facing EventsListComponent.
  def events_log_stream_body
    helpers.render(Admin::EventsListComponent.new(events: @events, endpoint: @log_endpoint, older_url: @older_url, newer_url: @newer_url))
  end

  def events_scope
    apply_filters(policy_scope(Event))
  end

  # The admin log navigates within the filter the operator is looking at.
  alias_method :navigable_events, :events_scope

  def permitted_filter_keys
    super + [:user_id]
  end
end
