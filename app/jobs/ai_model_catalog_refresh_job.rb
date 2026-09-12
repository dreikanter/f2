class AiModelCatalogRefreshJob < ApplicationJob
  queue_as :default

  def perform(run)
    return unless run.reload.running?
    return run.timeout! if run.deadline_at && run.deadline_at <= Time.current

    credential = run.subject
    original_key = credential.credential_data.fetch("api_key")
    begin
      models = AiModelCatalog.fetch(credential)
    rescue AiModelCatalog::Error => error
      Rails.error.report(error, context: { credential_id: credential.id })
    end

    credential.with_lock do
      return run.fail! unless credential.active? && credential.credential_data["api_key"] == original_key
      return run.timeout! if run.deadline_at && run.deadline_at <= Time.current

      if error
        run.fail! do |current|
          run.update!(context: { error: error.message, category: error.category, status: error.status }.compact)
          current.deactivate!(last_error: error.message) if error.invalid_key?
        end
      else
        run.succeed! do |current|
          current.update!(available_models: models, models_refreshed_at: Time.current)
        end
      end
    end
  end
end
