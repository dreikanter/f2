class FeedPreviewActivity
  attr_reader :event

  def initialize(preview)
    @event = Event.create!(type: "feed_preview", level: :info, user: preview.user,
                           subject: preview.ai_credential,
                           metadata: { status: "started", profile_key: preview.feed_profile_key })
  end

  def finish!(status:, stats:)
    return if @finished

    usage_costs = LlmUsage.where(id: event.event_references.where(reference_type: "LlmUsage").select(:reference_id))
                         .pluck(:cost_estimate_cents)
    totals = stats.dup
    if usage_costs.present?
      totals.merge!(llm_calls: usage_costs.size,
                    llm_cost_cents: usage_costs.any?(&:nil?) ? nil : usage_costs.sum)
    end
    search_count = event.event_references.where(reference_type: "Event").count
    totals[:search_calls] = search_count if search_count.positive?

    Event.transaction do
      # A fresh terminal event is discoverable by the activity cursor poller.
      completed = Event.create!(type: event.type, user: event.user, subject: event.subject,
                                level: status == "completed" ? :info : :warning,
                                metadata: event.metadata.merge("status" => status, "stats" => totals))
      event.event_references.update_all(event_id: completed.id, updated_at: Time.current)
      event.destroy!
      @event = completed
    end
    @finished = true
  end
end
