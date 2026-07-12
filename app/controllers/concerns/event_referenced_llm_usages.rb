module EventReferencedLlmUsages
  extend ActiveSupport::Concern

  private

  # The LLM calls this event accounts for, in call order. The matching stats
  # snapshot (llm_calls/llm_cost_cents) already lives on the event; this is the
  # per-call detail behind that total.
  def referenced_llm_usages(event)
    LlmUsage.where(id: event.event_references.where(reference_type: "LlmUsage").select(:reference_id))
            .order(:started_at)
  end
end
