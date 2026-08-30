# Validates an AiCredential against its provider by fetching its available
# models through LlmClient. Mirrors AccessTokenValidationJob: moves the
# credential through `validating → active | inactive` and records
# `last_validated_at` / `last_error` on the way. A successful fetch both
# proves the key works and gives us the model list to persist.
class AiCredentialValidationJob < ApplicationJob
  queue_as :default

  # @param credential_id [String, AiCredential] credential UUID; record accepted for queued legacy jobs
  # @param run_id [String, nil] validation UUID
  # @param fallback_state [String, nil] state to restore after an inconclusive check
  def perform(credential_id, run_id = nil, fallback_state = nil)
    credential = credential_id.is_a?(AiCredential) ? credential_id : AiCredential.find_by(id: credential_id)
    return unless credential

    claimed_run = credential.claim_validation!(run_id)
    return unless claimed_run

    run_id, inferred_fallback_state = claimed_run
    fallback_state ||= inferred_fallback_state

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
