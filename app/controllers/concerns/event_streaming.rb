module EventStreaming
  extend ActiveSupport::Concern

  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  included do
    class_attribute :events_page_size, default: 25
    class_attribute :brief_events_limit, default: 15
  end

  private

  # The most recent page of events. Polling always refreshes this first page;
  # older history is reached through cursor pagination, never by polling.
  # Preload event_references so feed refresh descriptions can count imported
  # posts without an extra query per row.
  def first_page_events
    events_scope.includes(:user, :subject, :event_references).order(created_at: :desc, id: :desc).limit(events_page_size)
  end

  def new_events?
    scope = events_scope
    scope = scope.where("id > ?", after_id) if after_id
    scope.exists?
  end

  def after_id
    event_cursor(:after_id)
  end

  # Event ids are uuids, but cursors arrive as untrusted params. Anything that
  # isn't a well-formed uuid (a stale link, a hand-edited "0") becomes nil, so
  # the id comparisons below never feed Postgres an invalid uuid.
  def event_cursor(key)
    value = params[key].to_s
    value if value.match?(UUID_FORMAT)
  end

  def render_events_stream
    return head :ok unless params[:force].present? || new_events?

    brief_display? ? render_brief_events_stream : render_full_events_stream
  end

  def render_full_events_stream
    load_stream_page
    render turbo_stream: turbo_stream.replace(events_log_dom_id, events_log_stream_body)
  end

  # Both logs share the bordered-list DOM id; admin overrides only the stream
  # body to render its richer Admin::EventsListComponent rows.
  def events_log_dom_id
    EventsListComponent::DOM_ID
  end

  def events_log_stream_body
    helpers.render(EventsListComponent.new(events: @events, endpoint: @log_endpoint, older_url: @older_url, newer_url: @newer_url))
  end

  # The brief list keeps its "View all" footer row across poll refreshes, so
  # the stream body must mirror the initial render on the status page.
  def render_brief_events_stream
    @events = events_scope.includes(:user, :subject, :event_references).order(created_at: :desc, id: :desc).limit(brief_events_limit)
    body = helpers.render(EventsListComponent.new(events: @events, endpoint: brief_polling_endpoint, view_all_url: events_log_path))
    render turbo_stream: turbo_stream.replace(EventsListComponent::DOM_ID, body)
  end

  def brief_display?
    params[:display] == "brief"
  end

  def brief_polling_endpoint
    events_log_path(format: :turbo_stream, display: :brief)
  end
end
