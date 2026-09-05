# A user's API credential for one AI provider. `credential_data` stores
# provider-specific fields (e.g. `{ "api_key" => "..." }`) and is encrypted at
# rest. Lifecycle, naming, and feed teardown come from ProviderCredential;
# model discovery and advisory metadata are specific to AI credentials.
class AiCredential < ApplicationRecord
  include ProviderCredential

  REMOVED_EVENT_TYPE = "feed_ai_credential_removed"
  DEACTIVATED_EVENT_TYPE = "ai_credential_deactivated"

  validates :provider, presence: true, inclusion: { in: ->(_) { LlmProvider.names } }

  def llm_provider
    LlmProvider.find(provider)
  end

  def provider_name
    llm_provider.display_name
  end

  MODEL_CATALOG_FRESHNESS = 1.day
  MODEL_REFRESH_TIMEOUT = 15.minutes

  def supported_models
    available_models.reject do |model|
      outputs = model.dig("metadata", "output_modalities")
      outputs.is_a?(Array) && outputs.any? && !outputs.include?("text")
    end
  end

  def model_metadata(model_id)
    available_models.find { |model| model["id"] == model_id }&.fetch("metadata", {}) || {}
  end

  def refresh_models_async(force: false)
    with_lock do
      return unless active?

      recent = latest_operation_run(:models_refresh)
      return recent if recent&.in_progress?(stale_after: MODEL_REFRESH_TIMEOUT)
      return if !force && models_refreshed_at && models_refreshed_at > MODEL_CATALOG_FRESHNESS.ago
      return if !force && recent && recent.created_at > 1.hour.ago

      run = OperationRun.start!(subject: self, kind: :models_refresh, timeout: MODEL_REFRESH_TIMEOUT)
      AiModelCatalogRefreshJob.perform_later(run)
      AiModelCatalogTimeoutJob.set(wait_until: run.deadline_at).perform_later(run)
      run
    end
  end

  def models_refreshing?
    latest_operation_run(:models_refresh)&.in_progress?(stale_after: MODEL_REFRESH_TIMEOUT) || false
  end

  def supports_model?(model_id)
    return false if model_id.blank?

    supported_models.any? { |model| model["id"] == model_id }
  end

  def default_supported_model
    provider_default = llm_provider.default_model
    return provider_default if supports_model?(provider_default)

    supported_models.first&.fetch("id")
  end

  def ruby_llm_context
    RubyLLM.context do |config|
      llm_provider.configure(config, credential_data["api_key"])
    end
  end

  # Provider listings can contain models newer than the SDK's bundled registry.
  # Let the provider resolve the exact ID instead of requiring an SDK update.
  def chat(model)
    context = ruby_llm_context
    # The client owns bounded fallback; SDK retries would multiply its attempts.
    context.config.max_retries = 0
    context.chat(
      model: model,
      provider: llm_provider.ruby_llm_provider,
      assume_model_exists: true
    )
  end
end
