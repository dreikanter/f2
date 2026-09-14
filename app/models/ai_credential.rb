# A user's encrypted credentials for one AI provider. Provider
# clients interpret credential fields; ProviderCredential supplies the shared
# lifecycle, naming, and feed teardown.
class AiCredential < ApplicationRecord
  include ProviderCredential

  has_many :llm_chats, dependent: :nullify

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

  private

  def provider_credentials_valid
    return unless LlmProvider.names.include?(provider)

    build_llm_client.credential_errors.each { |message| errors.add(:base, message) }
  end
end
