class RefreshLlmModelsJob < ApplicationJob
  limits_concurrency key: "model-registry", to: 1, on_conflict: :discard, duration: 30.minutes

  def perform
    refresh = LlmModelRefresh.current
    RubyLLM.models.refresh
    refresh.update!(refreshed_at: Time.current, failed_at: nil)
  rescue StandardError
    refresh&.update!(failed_at: Time.current)
    raise
  end
end
