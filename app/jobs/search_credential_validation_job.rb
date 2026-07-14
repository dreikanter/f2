# Validates a SearchCredential with one real, minimal search request. Search
# providers do not expose a free capabilities endpoint, so a one-result query
# is the smallest honest credential check.
class SearchCredentialValidationJob < ApplicationJob
  VALIDATION_QUERY = "Ruby programming language".freeze

  queue_as :default

  def perform(credential)
    credential.validating!
    credential.web_search_provider.search(VALIDATION_QUERY, max_results: 1)
    credential.record_search_call(purpose: :validation, outcome: :success)
    credential.update!(state: :active, last_validated_at: Time.current, last_error: nil)
  rescue WebSearchProvider::Error => e
    credential.record_search_call(purpose: :validation, outcome: :error, error: e.message)
    credential.deactivate!(last_error: e.message)
  end
end
