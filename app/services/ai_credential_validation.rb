# Runs credential validation through free model discovery. Settles the supplied
# OperationRun by activating the key and saving its catalog or applying failure policy.
class AiCredentialValidation
  include AiModelDiscovery

  private

  def save_catalog(models)
    run.succeed! do |credential|
      credential.update!(active: true, available_models: models, models_refreshed_at: Time.current,
                         last_validated_at: Time.current, last_error: nil)
      credential.active_operation_run(:models_refresh)&.supersede!
    end
  end

  def fail_discovery(error)
    run.fail! do |credential|
      run.update!(context: run.context.merge(error.details))
      if error.invalid_key?
        credential.deactivate!(last_error: error.message)
      else
        credential.update!(last_error: error.message)
      end
    end
  end
end
