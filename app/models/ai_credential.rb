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

  def credential_validator
    LlmProvider.find(provider).fetch(:validator_class).new(credential_data: credential_data)
  end

  def provider_credentials_valid
    return unless LlmProvider.names.include?(provider)

    credential_validator.errors.each { |message| errors.add(:base, message) }
  end
end
