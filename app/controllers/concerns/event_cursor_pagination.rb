module EventCursorPagination
  extend ActiveSupport::Concern

  # Streaming (first-page polling) and cursor pagination are two halves of the
  # same browsable, live-updating log, so they travel together.
  include EventStreaming

  private

  # Renders an HTML page of the log. A stale or hand-edited cursor can land on an
  # empty page; redirect back to the latest page instead of stranding the user.
  def render_events_page
    events = events_page

    if events.empty? && cursor_present?
      redirect_to events_log_path
    else
      build_page(events: events)
    end
  end

  def load_stream_page
    build_page(events: first_page_events)
  end

  # Cursor-based page: ordered chronologically (newest first) by `created_at`,
  # with `id` breaking ties. The cursor is an event id, but boundaries compare
  # the whole `(created_at, id)` tuple so a backdated event can't reorder pages.
  def events_page
    scope = events_scope.includes(:user, :subject, :event_references)

    if before_cursor
      scope.where(cursor_condition("<", before_cursor)).order(created_at: :desc, id: :desc).limit(events_page_size)
    elsif after_cursor
      scope.where(cursor_condition(">", after_cursor)).order(created_at: :asc, id: :asc).limit(events_page_size).reverse
    else
      scope.order(created_at: :desc, id: :desc).limit(events_page_size)
    end
  end

  # Compares each row's `(created_at, id)` against the cursor event's tuple, so
  # ordering is consistent even when id order diverges from created_at order.
  def cursor_condition(operator, cursor_id)
    Event.sanitize_sql_array([
      "(events.created_at, events.id) #{operator} (SELECT created_at, id FROM events WHERE id = ?)",
      cursor_id
    ])
  end

  # A page is "live" (and therefore polls) when nothing newer exists past its
  # top row, regardless of how the user arrived there.
  def build_page(events:)
    @events = events
    @older_url = older_page_url
    @newer_url = newer_page_url
    @offset = page_offset
    @log_endpoint = @newer_url.nil? ? polling_endpoint : nil
  end

  # How many newer events sit before the top of the current page, i.e. how far
  # into the log the user has paged. Zero on the latest page, which is also the
  # only page that polls — so the count never runs on the hot streaming path.
  def page_offset
    return 0 unless cursor_present?
    return 0 if @events.blank?

    events_scope.where(cursor_condition(">", @events.first.id)).count
  end

  def polling_endpoint
    events_log_path(format: :turbo_stream)
  end

  def older_page_url
    return if @events.blank?

    # The oldest row on the page is the last one in created_at-desc order.
    oldest_id = @events.last.id
    return unless events_scope.where(cursor_condition("<", oldest_id)).exists?

    events_log_path(before: oldest_id)
  end

  def newer_page_url
    return if @events.blank?

    newest_id = @events.first.id
    return unless events_scope.where(cursor_condition(">", newest_id)).exists?

    events_log_path(after: newest_id)
  end

  def cursor_present?
    before_cursor.present? || after_cursor.present?
  end

  def before_cursor
    event_cursor(:before)
  end

  def after_cursor
    event_cursor(:after)
  end
end
