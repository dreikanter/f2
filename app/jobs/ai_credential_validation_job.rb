class AiCredentialValidationJob < ApplicationJob
  queue_as :default

  # @param run [OperationRun] validation being performed
  def perform(run)
    return unless run.reload.running?
    return ProviderCredentialValidationTimeoutJob.perform_now(run) if run.deadline_at && run.deadline_at <= Time.current

    credential = run.subject
    original_key = credential.credential_data.fetch("api_key")
    models = AiModelCatalog.fetch(credential)

    with_current_credential(run, original_key) { save_catalog(run, models) }
  rescue LlmProvider::Error => error
    Rails.error.report(error, context: { credential_id: credential.id })
    with_current_credential(run, original_key) { fail_validation(run, error) }
  end

  private

  def with_current_credential(run, original_key)
    run.subject.with_lock do
      credential = run.subject
      return run.fail! unless credential.credential_data["api_key"] == original_key
      return ProviderCredentialValidationTimeoutJob.perform_now(run) if run.deadline_at && run.deadline_at <= Time.current

      yield
    end
  end

  def save_catalog(run, models)
    run.succeed! do |credential|
      credential.update!(state: :active, available_models: models, models_refreshed_at: Time.current,
                         last_validated_at: Time.current, last_error: nil)
    end
  end

  def fail_validation(run, error)
    run.fail! do |credential|
      run.update!(context: run.context.merge(error.details))
      if error.invalid_key?
        credential.deactivate!(last_error: error.message)
      else
        credential.update!(state: run.context.fetch("fallback_state"), last_error: error.message)
      end
    end
  end
end
