class ProviderCredentialValidationTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param credential [AiCredential, SearchCredential] credential being validated
  # @param run_id [String] validation UUID captured when the run started
  # @param fallback_state [String] state to restore without judging the key
  def perform(credential, run_id, fallback_state)
    credential.timeout_validation!(run_id: run_id, fallback_state: fallback_state)
  end
end
