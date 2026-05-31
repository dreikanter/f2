module EventStreaming
  extend ActiveSupport::Concern

  included do
    class_attribute :stream_events_limit, default: 100
  end

  private

  # Events to render: while polling for the "next window" we ascend from the
  # client's threshold so nothing is duplicated or skipped; otherwise we return
  # the most recent batch.
  def events_for_log
    scope = events_scope.includes(:user, :subject)

    if streaming? && next_event_window?
      scope.where("events.id > ?", after_id).order(id: :asc).limit(stream_events_limit).to_a.reverse
    else
      scope.order(id: :desc).limit(events_log_limit)
    end
  end

  # True when more than a full page of unseen events exists past the threshold.
  # In that case the whole list is replaced with the oldest unseen window.
  def next_event_window?
    return false if params[:force].present?
    return false unless after_id.positive?

    events_scope.where("events.id > ?", after_id).limit(stream_events_limit + 1).count > stream_events_limit
  end

  def new_events?
    after_id < events_scope.maximum(:id).to_i
  end

  def after_id
    params[:after_id].to_i
  end

  def streaming?
    request.format.turbo_stream?
  end

  # Override to vary the batch size for non-streaming requests (e.g. an initial
  # HTML page load).
  def events_log_limit
    stream_events_limit
  end

  def render_events_stream
    return head :ok unless params[:force].present? || new_events?

    component = event_log_component
    body = helpers.render(component) do |log|
      @events.each { |event| log.with_entry { helpers.render(entry_component(event)) } }
    end
    render turbo_stream: turbo_stream.replace(component.dom_id, body)
  end
end
