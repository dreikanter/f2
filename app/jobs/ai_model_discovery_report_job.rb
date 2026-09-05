class AiModelDiscoveryReportJob < ApplicationJob
  include RecordsJobRun
  include RunsAsMaintenanceJob

  queue_as :default

  def self.description
    "Lists models using one active staging credential per provider, from any account. " \
      "Uses free model-listing requests only. Open the finished run and copy its details to share the report."
  end

  def perform
    raise "Model discovery reports require staging" unless Rails.env.staging?

    results = LlmProvider.all.map { |provider| discover(provider) }
    record_event(
      type: "job.ai_model_discovery_report.completed",
      message: results.map { |result| "#{result[:provider]}: #{result[:status]}" }.join(", "),
      level: results.any? { |result| result[:status] == "FAIL" } ? :warning : :info,
      environment: Rails.env.to_s,
      revision: ENV["APP_REVISION"].presence,
      ruby_version: RUBY_VERSION,
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s,
      generated_at: Time.current.iso8601,
      results: results
    )
  end

  private

  def discover(provider)
    credential = AiCredential.active.where(provider: provider.name).order(:created_at, :id).first
    return { provider: provider.name, status: "SKIP", note: "No active staging credential" } unless credential

    models = LlmClient.for(credential).available_models.sort_by { |model| model.fetch("id") }
    {
      provider: provider.name,
      status: models.empty? ? "FAIL" : "PASS",
      note: models.empty? ? "Models listing was empty" : "Models listing completed",
      sdk_provider: provider.ruby_llm_provider.to_s,
      assume_model_exists: provider.assume_model_exists?,
      model_count: models.size,
      models_without_capability_metadata: models.count { |model| !model.key?("capabilities") },
      metadata_source: "LlmClient model serialization; may include SDK registry metadata",
      models: models
    }
  rescue StandardError => e
    Rails.error.report(e, context: { provider: provider.name })
    # Provider errors can echo request credentials, so only the error class is shareable.
    { provider: provider.name, status: "FAIL", error_class: e.class.name,
      note: "Models listing failed; details were sent to error reporting" }
  end
end
