class RefreshLlmModelsJob < ApplicationJob
  limits_concurrency key: "model-registry", to: 1, on_conflict: :discard, duration: 30.minutes

  def perform
    RubyLLM.models.refresh
  end
end
