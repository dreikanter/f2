class FeedPreviewActivity
  attr_reader :event

  def initialize(preview)
    @event = Event.create!(type: "feed_preview", level: :info, user: preview.user,
                           subject: preview.feed || preview.ai_credential,
                           metadata: { status: "started", profile_key: preview.feed_profile_key })
  end

  def finish!(status:, stats:, error: nil)
    return if @finished

    usage_costs = LlmUsage.where(id: event.event_references.where(reference_type: "LlmUsage").select(:reference_id))
                         .pluck(:cost_estimate_cents)
    totals = stats.dup
    if usage_costs.present?
      # Keep the JSON snapshot numeric; Rails encodes BigDecimal as a string.
      totals.merge!(llm_calls: usage_costs.size,
                    llm_cost_cents: usage_costs.any?(&:nil?) ? nil : usage_costs.sum.to_f)
    end
    search_count = event.event_references.where(reference_type: "Event").count
    totals[:search_calls] = search_count if search_count.positive?

    metadata = event.metadata.merge("status" => status, "stats" => totals)
    if error
      metadata["error"] = {
        class: error.class.name,
        message: error.message,
        stage: stats[:failed_at_step].to_s,
        backtrace: error.backtrace
      }
    end

    Event.transaction do
      completed = Event.create!(
        type: event.type,
        user: event.user,
        subject: event.subject,
        level: status == "completed" ? :info : :warning,
        message: error&.message.to_s,
        metadata: metadata
      )

      event.event_references.update_all(event_id: completed.id, updated_at: Time.current)
      event.destroy!
      @event = completed
    end
    @finished = true
  end
end
