class AiCredentialValidation
  attr_reader :run

  # @param run [OperationRun] validation being performed
  def initialize(run)
    @run = run
  end

  def credential
    run.subject
  end

  def call
    return unless run.reload.running?
    return credential.timeout_validation!(run: run) if run.deadline_at && run.deadline_at <= Time.current

    original_key = credential.credential_data.fetch("api_key")
    models = AiModelCatalog.fetch(credential)

    with_current_credential(original_key) { save_catalog(models) }
  rescue LlmProvider::Error => error
    Rails.error.report(error, context: { credential_id: credential.id })
    with_current_credential(original_key) { fail_validation(error) }
  end

  private

  def with_current_credential(original_key)
    credential.with_lock do
      return run.fail! unless credential.credential_data["api_key"] == original_key
      return credential.timeout_validation!(run: run) if run.deadline_at && run.deadline_at <= Time.current

      yield
    end
  end

  def save_catalog(models)
    run.succeed! do |credential|
      credential.update!(state: :active, available_models: models, models_refreshed_at: Time.current,
                         last_validated_at: Time.current, last_error: nil)
    end
  end

  def fail_validation(error)
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
