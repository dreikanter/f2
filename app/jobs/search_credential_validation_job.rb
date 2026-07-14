# Validates a SearchCredential with one real, minimal search request. Search
# providers do not expose a free capabilities endpoint, so a one-result query
# is the smallest honest credential check.
class SearchCredentialValidationJob < ApplicationJob
  VALIDATION_QUERY = "Ruby programming language".freeze

  queue_as :default

  def perform(credential)
    credential.validating!
    credential.web_search_provider.search(VALIDATION_QUERY, max_results: 1)
    credential.update!(state: :active, last_validated_at: Time.current, last_error: nil)
    record_call(credential, outcome: :success)
  rescue WebSearchProvider::Error => e
    credential.deactivate!(last_error: e.message)
    record_call(credential, outcome: :error, error: e.message)
  end

  private

  # Best-effort, after the state transition: accounting must never leave a
  # credential stuck in validating.
  def record_call(credential, outcome:, error: nil)
    Rails.error.handle(StandardError, context: { search_credential_id: credential.id }) do
      credential.record_search_call(purpose: :validation, outcome: outcome, error: error)
    end
  end
end
