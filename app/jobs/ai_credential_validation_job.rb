# Validates an AiCredential against its provider by fetching its available
# models through LlmClient. Mirrors AccessTokenValidationJob: moves the
# credential through `validating → active | inactive` and records
# `last_validated_at` / `last_error` on the way. A successful fetch both
# proves the key works and gives us the model list to persist.
class AiCredentialValidationJob < ApplicationJob
  queue_as :default

  def perform(credential)
    credential.validating!

    models = LlmClient.for(credential).available_models
    credential.update!(state: :active, available_models: models,
                       last_validated_at: Time.current, last_error: nil)
  rescue LlmClient::Error => e
    credential.disable_credential_and_feeds(last_error: e.message)
  end
end
