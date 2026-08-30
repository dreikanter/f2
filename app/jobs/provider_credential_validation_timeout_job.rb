class ProviderCredentialValidationTimeoutJob < ApplicationJob
  queue_as :timeouts

  CREDENTIAL_CLASSES = {
    "AiCredential" => AiCredential,
    "SearchCredential" => SearchCredential
  }.freeze

  # @param credential_type [String] supported credential class name
  # @param credential_id [String] credential UUID
  # @param run_id [String] validation UUID captured when the run started
  # @param fallback_state [String] state to restore without judging the key
  def perform(credential_type, credential_id, run_id, fallback_state)
    credential = CREDENTIAL_CLASSES.fetch(credential_type).find_by(id: credential_id)
    credential&.timeout_validation!(run_id: run_id, fallback_state: fallback_state)
  end
end
