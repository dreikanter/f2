# Runs credential validation through free model discovery. Settles the supplied
# OperationRun by activating the key and saving its catalog or applying failure policy.
class AiCredentialValidation
  # @param run [OperationRun] validation being performed
  def initialize(run)
    @run = run
  end

  def call
    return unless run.reload.running?
    return run.timeout_credential_validation! if run.timeout?

    original_data = credential.credential_data.deep_dup
    models = AiModelCatalog.fetch(credential)

    with_current_credential(original_data) { save_catalog(models) }
  rescue LlmProvider::Error => error
    Rails.error.report(error, context: { credential_id: credential.id })
    with_current_credential(original_data) { fail_validation(error) }
  end

  private

  attr_reader :run

  def credential
    run.subject
  end

  def with_current_credential(original_data)
    credential.with_lock do
      return run.fail! unless credential.credential_data == original_data
      return run.timeout_credential_validation! if run.timeout?

      yield
    end
  end

  def save_catalog(models)
    run.succeed! do |credential|
      credential.update!(state: :active, available_models: models, models_refreshed_at: Time.current,
                         last_validated_at: Time.current, last_error: nil)
      credential.active_operation_run(:models_refresh)&.supersede!
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
