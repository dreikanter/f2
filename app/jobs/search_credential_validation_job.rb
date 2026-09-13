# Validates a SearchCredential with one real, minimal search request. Search
# providers do not expose a free capabilities endpoint, so a one-result query
# is the smallest honest credential check.
class SearchCredentialValidationJob < ApplicationJob
  VALIDATION_QUERY = "Ruby programming language".freeze

  queue_as :default

  # @param run [OperationRun] validation being performed
  def perform(run)
    return unless run.reload.running?
    return run.timeout! if run.deadline_reached?

    credential = run.subject
    original_data = credential.credential_data.deep_dup
    record_usage(credential)
    credential.web_search_provider.search(VALIDATION_QUERY, max_results: 1)
    with_current_credential(run, original_data) do
      run.succeed! do |current_credential|
        current_credential.update!(active: true, last_validated_at: Time.current, last_error: nil)
      end
    end
  rescue WebSearchProvider::Error => error
    with_current_credential(run, original_data) do
      credential.deactivate!(last_error: error.message, run: run)
    end
  end

  private

  def with_current_credential(run, original_data)
    run.subject.with_lock do
      return run.supersede! unless run.subject.credential_data == original_data
      return run.timeout! if run.deadline_reached?

      yield
    end
  end

  # Best-effort: an accounting failure is not a WebSearchProvider::Error, so
  # unguarded it would leave validation running and bill another query on retry.
  def record_usage(credential)
    Rails.error.handle(StandardError, context: { search_credential_id: credential.id }) do
      WebSearchUsage.record!(credential: credential)
    end
  end
end
