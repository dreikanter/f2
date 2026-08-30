# A user's API credential for one AI provider. `credential_data` stores
# provider-specific fields (e.g. `{ "api_key" => "..." }`) and is encrypted at
# rest. Lifecycle, naming, and feed teardown come from ProviderCredential;
# what's here is the model-capability side: which models this key may actually
# run.
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

  # Models this credential can actually back a feed with: the dev-verified
  # capability matrix intersected with the provider's live snapshot.
  # Membership is qualification — a snapshot model absent from the matrix (or a
  # provider with no matrix rows) yields nothing, so nothing unverified leaks
  # into the picker or a run.
  def supported_models
    verified = LlmModelCapability.models_for(provider)
    available_models.select { |model| verified.include?(model["id"]) }
  end

  def supports_model?(model_id)
    return false if model_id.blank?

    supported_models.any? { |model| model["id"] == model_id }
  end

  # The model to fall back to when a chosen model is no longer supported: the
  # provider's configured default when it's still supported here, otherwise the
  # first supported model, or nil when the provider has no verified models.
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

  # The chat a run is made on: this key, its provider's RubyLLM key, and its
  # model-existence rule. Shared so a probe cannot qualify a model on a
  # configuration production doesn't use.
  def chat(model)
    ruby_llm_context.chat(
      model: model,
      provider: llm_provider.ruby_llm_provider,
      assume_model_exists: llm_provider.assume_model_exists?
    )
  end
end
