class RefreshLlmModelsJob < ApplicationJob
  limits_concurrency key: "model-registry", to: 1, on_conflict: :discard, duration: 30.minutes

  def perform
    RubyLLM.models.refresh
    LlmModelRefresh.current.update!(refreshed_at: Time.current, failed_at: nil)
  rescue StandardError => e
    Rails.error.report(e)
    LlmModelRefresh.current.update!(failed_at: Time.current)
    raise
  end
end
