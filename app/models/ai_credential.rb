# A user's encrypted credentials and model catalog for one AI provider. Provider
# clients interpret credential fields; ProviderCredential supplies the shared
# lifecycle, naming, and feed teardown.
class AiCredential < ApplicationRecord
  include ProviderCredential

  REMOVED_EVENT_TYPE = "feed_ai_credential_removed"
  DEACTIVATED_EVENT_TYPE = "ai_credential_deactivated"

  validates :provider, presence: true, inclusion: { in: ->(_) { LlmProvider.names } }
  validate :provider_credentials_valid

  def build_llm_client
    LlmProvider.build(provider, credential_data: credential_data)
  end

  def provider_name
    LlmProvider.find(provider).fetch(:display_name)
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

  def ruby_llm_context
    build_llm_client.context
  end

  def refresh_models_async(force: false)
    return unless force && active?

    run = OperationRun.start!(subject: self, kind: :models_refresh)
    AiModelCatalogRefreshJob.perform_now(run)
    run
  end

  def models_refreshing?
    latest_operation_run(:models_refresh)&.in_progress?(stale_after: MODEL_REFRESH_TIMEOUT) || false
  end

  def supports_model?(model_id)
    return false if model_id.blank?

    supported_models.any? { |model| model["id"] == model_id }
  end

  def default_supported_model
    provider_default = LlmProvider.find(provider).fetch(:default_model)
    return provider_default if supports_model?(provider_default)

    supported_models.first&.fetch("id")
  end

  private

  def provider_credentials_valid
    return unless LlmProvider.names.include?(provider)

    build_llm_client.credential_errors.each { |message| errors.add(:base, message) }
  end
end
