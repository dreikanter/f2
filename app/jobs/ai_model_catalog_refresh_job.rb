class AiModelCatalogRefreshJob < ApplicationJob
  queue_as :default

  def perform(run)
    return unless run.running?
    return run.timeout! if run.deadline_at <= Time.current

    credential = run.subject
    original_key = credential.credential_data
    models = AiModelCatalog.fetch(credential)

    credential.with_lock do
      if run.deadline_at <= Time.current
        run.timeout!
      elsif credential.active? && credential.credential_data == original_key
        run.succeed! do |current|
          current.update!(available_models: models, models_refreshed_at: Time.current)
        end
      else
        run.fail!
      end
    end
  rescue LlmClient::Error => e
    Rails.error.report(e, context: { credential_id: credential.id })
    run.fail! { run.update!(context: { error_class: e.class.name }) }
  end
end
