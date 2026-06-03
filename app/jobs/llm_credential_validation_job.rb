# Validates an LlmCredential against its provider by issuing a cheap
# health-check call through LlmClient. Mirrors AccessTokenValidationJob:
# moves the credential through `validating → active | inactive` and records
# `last_validated_at` / `last_error` on the way.
class LlmCredentialValidationJob < ApplicationJob
  queue_as :default

  def perform(credential)
    credential.validating!

    LlmClient.for(credential).health_check
    credential.update!(state: :active, last_validated_at: Time.current, last_error: nil)
  rescue LlmClient::Error => e
    credential.update!(state: :inactive, last_validated_at: Time.current, last_error: e.message)
  end
end
