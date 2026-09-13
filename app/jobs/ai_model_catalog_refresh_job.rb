class AiModelCatalogRefreshJob < ApplicationJob
  queue_as :default

  def perform(run)
    return unless run.reload.running?
    return run.timeout! if run.deadline_at && run.deadline_at <= Time.current

    credential = run.subject
    original_key = credential.credential_data.fetch("api_key")
    models = AiModelCatalog.fetch(credential)

    with_current_credential(run, original_key) { save_catalog(run, models) }
  rescue LlmProvider::Error => error
    Rails.error.report(error, context: { credential_id: credential.id })
    with_current_credential(run, original_key) { fail_refresh(run, error) }
  end

  private

  def with_current_credential(run, original_key)
    run.subject.with_lock do
      credential = run.subject
      return run.fail! unless credential.active? && credential.credential_data["api_key"] == original_key
      return run.timeout! if run.deadline_at && run.deadline_at <= Time.current

      yield
    end
  end

  def save_catalog(run, models)
    run.succeed! do |credential|
      credential.update!(available_models: models, models_refreshed_at: Time.current)
    end
  end

  def fail_refresh(run, error)
    run.fail! do |credential|
      run.update!(context: run.context.merge(error.details))
      credential.deactivate!(last_error: error.message) if error.invalid_key?
    end
  end
end
