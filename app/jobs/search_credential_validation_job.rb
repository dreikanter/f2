# Validates a SearchCredential with one real, minimal search request. Search
# providers do not expose a free capabilities endpoint, so a one-result query
# is the smallest honest credential check.
class SearchCredentialValidationJob < ApplicationJob
  VALIDATION_QUERY = "Ruby programming language".freeze

  queue_as :default

  def perform(credential)
    credential.validating!
    record_usage(credential)
    credential.web_search_provider.search(VALIDATION_QUERY, max_results: 1)
    credential.update!(state: :active, last_validated_at: Time.current, last_error: nil)
  rescue WebSearchProvider::Error => e
    credential.deactivate!(last_error: e.message)
  end

  private

  # Best-effort: an accounting failure is not a WebSearchProvider::Error, so
  # unguarded it would escape the rescue, strand the credential in
  # "validating", and burn another billed query on every retry.
  def record_usage(credential)
    Rails.error.handle(StandardError, context: { search_credential_id: credential.id }) do
      WebSearchUsage.record!(credential: credential)
    end
  end
end
