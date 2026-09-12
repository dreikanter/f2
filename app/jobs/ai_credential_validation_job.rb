class AiCredentialValidationJob < ApplicationJob
  queue_as :default

  # @param run [OperationRun] validation being performed
  def perform(run)
    return unless run.reload.running?
    return ProviderCredentialValidationTimeoutJob.perform_now(run) if run.deadline_at && run.deadline_at <= Time.current

    credential = run.subject
    original_key = credential.credential_data.fetch("api_key")
    begin
      models = AiModelCatalog.fetch(credential)
    rescue AiModelCatalog::Error => error
      Rails.error.report(error, context: { credential_id: credential.id })
    end

    credential.with_lock do
      return run.fail! unless credential.credential_data["api_key"] == original_key
      return ProviderCredentialValidationTimeoutJob.perform_now(run) if run.deadline_at && run.deadline_at <= Time.current

      if error&.invalid_key?
        credential.deactivate!(last_error: error.message, run: run)
      elsif error
        run.fail! do |current|
          current.update!(state: run.context.fetch("fallback_state"), last_error: error.message)
        end
      else
        run.succeed! do |current|
          current.update!(state: :active, available_models: models, models_refreshed_at: Time.current,
                          last_validated_at: Time.current, last_error: nil)
        end
      end
    end
  end
end
