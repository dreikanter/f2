# Refreshes an active credential's catalog for an OperationRun. Preserves the
# saved state on transient failure and deactivates a confirmed invalid key.
class AiModelCatalogRefresh
  # @param run [OperationRun] model catalog refresh being performed
  def initialize(run)
    @run = run
  end

  def call
    return unless run.reload.running?
    return run.timeout! if run.timeout?

    original_data = credential.credential_data.deep_dup
    models = AiModelCatalog.fetch(credential)

    with_current_credential(original_data) { save_catalog(models) }
  rescue LlmProvider::Error => error
    Rails.error.report(error, context: { credential_id: credential.id })
    with_current_credential(original_data) { fail_refresh(error) }
  end

  private

  attr_reader :run

  def credential
    run.subject
  end

  def with_current_credential(original_data)
    credential.with_lock do
      return run.supersede! unless credential.active? && credential.credential_data == original_data
      return run.timeout! if run.timeout?

      yield
    end
  end

  def save_catalog(models)
    run.succeed! do |credential|
      credential.update!(available_models: models, models_refreshed_at: Time.current)
    end
  end

  def fail_refresh(error)
    run.fail! do |credential|
      run.update!(context: run.context.merge(error.details))
      credential.deactivate!(last_error: error.message) if error.invalid_key?
    end
  end
end
