# Validates an AiCredential against its provider by fetching its available
# models through LlmClient. Mirrors AccessTokenValidationJob: moves the
# credential through `validating → active | inactive` and records
# `last_validated_at` / `last_error` on the way. A successful fetch both
# proves the key works and gives us the model list to persist.
class AiCredentialValidationJob < ApplicationJob
  queue_as :default

  # @param credential [AiCredential] credential being validated
  # @param run_id [String] validation UUID
  # @param fallback_state [String] state to restore after an inconclusive check
  def perform(credential, run_id, fallback_state)
    return unless credential.validation_run?(run_id)

    # Both alternatives are terminal: the validation page polls silently while a
    # credential is pending or validating, so leaving it either way would spin
    # forever without ever showing the error.
    models = LlmClient.for(credential).available_models
    credential.settle_validation!(
      run_id: run_id,
      state: :active,
      available_models: models,
      last_validated_at: Time.current,
      last_error: nil
    )
  rescue LlmClient::AuthError => e
    # Must precede the provider error it descends from. A rejected key is dead,
    # and a dead key cannot back a running feed.
    credential.deactivate!(last_error: e.message, run_id: run_id)
  rescue LlmClient::Error => e
    # Everything else says nothing about the key, so the feeds stay up — this
    # deliberately does not take the deactivate! path.
    credential.settle_validation!(run_id: run_id, state: fallback_state, last_error: e.message)
  end
end
