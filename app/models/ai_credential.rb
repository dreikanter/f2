# A user's encrypted credentials for one AI provider. Delegates credential
# checks to its registered validator; ProviderCredential supplies the shared
# lifecycle, naming, and feed teardown.
class AiCredential < ApplicationRecord
  include ProviderCredential

  has_many :llm_chats, dependent: :nullify

  REMOVED_EVENT_TYPE = "feed_ai_credential_removed"
  DEACTIVATED_EVENT_TYPE = "ai_credential_deactivated"

  validates :provider, presence: true, inclusion: { in: ->(_) { LlmProvider.names } }
  validate :provider_credentials_valid
  validate :default_model_listed, if: -> { default_model.present? && (will_save_change_to_default_model? || will_save_change_to_provider?) }

  normalizes :default_model, with: ->(value) { value.strip.presence }

  def build_llm_provider
    LlmProvider.build(provider, credential_data: credential_data)
  end

  # @return [Boolean] true when the provider accepts the credentials
  # @raise [AiCredentialValidator::Error] when authentication cannot be confirmed
  def validate_credentials!
    credential_validator.validate!
  end

  def provider_name
    LlmProvider.find(provider).fetch(:display_name)
  end

  private

  def default_model_listed
    return if LlmModels.for_feed(provider).any? { |model| model.id == default_model }

    errors.add(:default_model, "Choose a model from this provider's list.")
  end

  def credential_validator
    LlmProvider.find(provider).fetch(:validator_class).new(credential_data: credential_data)
  end

  def provider_credentials_valid
    return unless LlmProvider.names.include?(provider)

    credential_validator.errors.each { |message| errors.add(:base, message) }
  end
end
