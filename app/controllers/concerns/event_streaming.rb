module EventStreaming
  extend ActiveSupport::Concern

  included do
    class_attribute :events_page_size, default: 25
  end

  private

  # The most recent page of events. Polling always refreshes this first page;
  # older history is reached through cursor pagination, never by polling.
  def first_page_events
    events_scope.includes(:user, :subject).order(created_at: :desc, id: :desc).limit(events_page_size)
  end

  def new_events?
    after_id < events_scope.maximum(:id).to_i
  end

  def after_id
    params[:after_id].to_i
  end

  def render_events_stream
    return head :ok unless params[:force].present? || new_events?

    load_stream_page
    body = helpers.render(event_log_component) do |log|
      @events.each { |event| log.with_entry { helpers.render(entry_component(event)) } }
    end
    render turbo_stream: turbo_stream.replace(EventLogComponent::DOM_ID, body)
  end
end
