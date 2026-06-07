module EventStreaming
  extend ActiveSupport::Concern

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
    after_id < events_scope.maximum(:id).to_i
  end

  def after_id
    params[:after_id].to_i
  end

  def render_events_stream
    return head :ok unless params[:force].present? || new_events?

    brief_display? ? render_brief_events_stream : render_full_events_stream
  end

  def render_full_events_stream
    load_stream_page
    render turbo_stream: turbo_stream.replace(events_log_dom_id, events_log_stream_body)
  end

  # The user-facing log renders as a bordered list; admin overrides both to keep
  # its card layout (EventLogComponent).
  def events_log_dom_id
    EventsListComponent::DOM_ID
  end

  def events_log_stream_body
    helpers.render(EventsListComponent.new(events: @events, endpoint: @log_endpoint, older_url: @older_url, newer_url: @newer_url))
  end

  def render_brief_events_stream
    @events = events_scope.includes(:user, :subject, :event_references).order(created_at: :desc, id: :desc).limit(brief_events_limit)
    body = helpers.render(EventsListComponent.new(events: @events, endpoint: brief_polling_endpoint))
    render turbo_stream: turbo_stream.replace(EventsListComponent::DOM_ID, body)
  end

  def brief_display?
    params[:display] == "brief"
  end

  def brief_polling_endpoint
    events_log_path(format: :turbo_stream, display: :brief)
  end
end
