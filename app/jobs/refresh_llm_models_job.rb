class RefreshLlmModelsJob < ApplicationJob
  include RecordsJobRun
  include RunsAsMaintenanceJob

  limits_concurrency key: "model-registry", to: 1, on_conflict: :discard, duration: 30.minutes

  def self.display_name = "Refresh LLM Models"

  def self.description = "Downloads the shared model catalog and replaces the stored models."

  def perform
    RubyLLM.models.refresh
    LlmModelRefresh.current.update!(refreshed_at: Time.current, failed_at: nil)
    model_count = RubyLLM::ActiveRecord::Model.count
    record_event(type: "job.refresh_llm_models.completed",
                 message: "Stored #{model_count} models",
                 model_count: model_count)
  rescue StandardError => e
    Rails.error.report(e)
    LlmModelRefresh.current.update!(failed_at: Time.current)
    raise
  end
end
