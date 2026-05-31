class Admin::EventsController < ApplicationController
  include EventFiltering
  include EventStreaming

  def index
    authorize Event

    @filter = optional_filter

    respond_to do |format|
      format.html { build_page(events: events_page, first_page: first_page?) }
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

  def load_stream_page
    build_page(events: first_page_events, first_page: true)
  end

  # Cursor-based page: ordered by id desc, scoped by an optional `before`/`after`
  # event id so page boundaries stay stable as new events arrive.
  def events_page
    scope = events_scope.includes(:user, :subject)

    if before_cursor.positive?
      scope.where("events.id < ?", before_cursor).order(id: :desc).limit(events_page_size)
    elsif after_cursor.positive?
      scope.where("events.id > ?", after_cursor).order(id: :asc).limit(events_page_size).reverse
    else
      scope.order(id: :desc).limit(events_page_size)
    end
  end

  def build_page(events:, first_page:)
    @events = events
    @log_endpoint = first_page ? polling_endpoint : nil
    @older_url = older_page_url
    @newer_url = first_page ? nil : newer_page_url
  end

  def event_log_component
    EventLogComponent.new(events: @events, endpoint: @log_endpoint, older_url: @older_url, newer_url: @newer_url)
  end

  def entry_component(event)
    Admin::EventLogEntryComponent.new(event: event, href: admin_event_path(event))
  end

  def polling_endpoint
    admin_events_path(format: :turbo_stream, filter: optional_filter.to_h.presence)
  end

  def older_page_url
    return if @events.blank?

    oldest_id = @events.map(&:id).min
    return unless events_scope.where("events.id < ?", oldest_id).exists?

    admin_events_path(filter: optional_filter.to_h.presence, before: oldest_id)
  end

  def newer_page_url
    return if @events.blank?

    newest_id = @events.map(&:id).max
    return unless events_scope.where("events.id > ?", newest_id).exists?

    admin_events_path(filter: optional_filter.to_h.presence, after: newest_id)
  end

  def first_page?
    before_cursor.zero? && after_cursor.zero?
  end

  def before_cursor
    params[:before].to_i
  end

  def after_cursor
    params[:after].to_i
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
