# Validates an AiCredential against its provider by fetching its available
# models through LlmClient. Mirrors AccessTokenValidationJob: moves the
# credential through `validating → active | inactive` and records
# `last_validated_at` / `last_error` on the way. A successful fetch both
# proves the key works and gives us the model list to persist.
class AiCredentialValidationJob < ApplicationJob
  queue_as :default

  # @param run [OperationRun] validation being performed
  def perform(run)
    return unless run.running?

    credential = run.subject

    # Both alternatives are terminal: the validation page polls silently while a
    # credential is pending or validating, so leaving it either way would spin
    # forever without ever showing the error.
    models = LlmClient.for(credential).available_models
    succeeded = run.succeed! do |current_credential|
      current_credential.update!(
        state: :active,
        available_models: models,
        models_refreshed_at: nil,
        last_validated_at: Time.current,
        last_error: nil
      )
    end
    credential.refresh_models_async(force: true) if succeeded
  rescue LlmClient::AuthError => e
    # Must precede the provider error it descends from. A rejected key is dead,
    # and a dead key cannot back a running feed.
    credential.deactivate!(last_error: e.message, run: run)
  rescue LlmClient::Error => e
    # Everything else says nothing about the key, so the feeds stay up — this
    # deliberately does not take the deactivate! path.
    run.fail! do |current_credential|
      current_credential.update!(state: run.context.fetch("fallback_state"), last_error: e.message)
    end
  end
end
