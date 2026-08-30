# Validates a SearchCredential with one real, minimal search request. Search
# providers do not expose a free capabilities endpoint, so a one-result query
# is the smallest honest credential check.
class SearchCredentialValidationJob < ApplicationJob
  VALIDATION_QUERY = "Ruby programming language".freeze

  queue_as :default

  # @param credential_id [String, SearchCredential] credential UUID; record accepted for queued legacy jobs
  # @param run_id [String, nil] validation UUID
  # @param _fallback_state [String, nil] state captured for the timeout job
  def perform(credential_id, run_id = nil, _fallback_state = nil)
    credential =
      if credential_id.is_a?(SearchCredential)
        credential_id
      else
        SearchCredential.find_by(id: credential_id)
      end
    return unless credential

    claimed_run = credential.claim_validation!(run_id)
    return unless claimed_run

    run_id = claimed_run.first

    record_usage(credential)
    credential.web_search_provider.search(VALIDATION_QUERY, max_results: 1)
    credential.settle_validation!(
      run_id: run_id,
      state: :active,
      last_validated_at: Time.current,
      last_error: nil
    )
  rescue WebSearchProvider::Error => e
    credential.deactivate!(last_error: e.message, run_id: run_id)
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
