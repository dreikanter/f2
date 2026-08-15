# Validates an AiCredential against its provider by fetching its available
# models through LlmClient. Mirrors AccessTokenValidationJob: moves the
# credential through `validating → active | inactive` and records
# `last_validated_at` / `last_error` on the way. A successful fetch both
# proves the key works and gives us the model list to persist.
class AiCredentialValidationJob < ApplicationJob
  queue_as :default

  def perform(credential)
    # Never "validating": restoring that would re-strand a credential a
    # previous run left stuck.
    fallback_state = credential.active? ? :active : :pending
    credential.validating!

    models = LlmClient.for(credential).available_models
    credential.update!(state: :active, available_models: models,
                       last_validated_at: Time.current, last_error: nil)
  rescue LlmClient::AuthError => e
    # Must precede the provider error it descends from. A rejected key is dead,
    # and a dead key cannot back a running feed.
    credential.deactivate!(last_error: e.message)
  rescue LlmClient::Error => e
    # Everything else says nothing about the key, so the feeds stay up.
    credential.update!(state: fallback_state, last_error: e.message)
  end
end
