# Validates an AiCredential against its provider by fetching its available
# models through LlmClient. Mirrors AccessTokenValidationJob: moves the
# credential through `validating → active | inactive` and records
# `last_validated_at` / `last_error` on the way. A successful fetch both
# proves the key works and gives us the model list to persist.
class AiCredentialValidationJob < ApplicationJob
  queue_as :default

  def perform(credential)
    previous_state = credential.state
    credential.validating!

    models = LlmClient.for(credential).available_models
    credential.update!(state: :active, available_models: models,
                       last_validated_at: Time.current, last_error: nil)
  rescue LlmClient::AuthError => e
    # A rejected key is dead, and a dead key cannot back a running feed.
    # Matched before the provider error it descends from.
    credential.deactivate!(last_error: e.message)
  rescue LlmClient::Error => e
    # A timeout, a 429 or a provider fault says nothing about the key — and
    # low-tier accounts are rate-limited often enough that treating one as a
    # dead key would take a user's feeds down routinely. Record it, put the
    # credential back where it was, and leave the feeds alone.
    credential.update!(state: previous_state, last_error: e.message)
  end
end
