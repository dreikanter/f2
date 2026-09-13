# Refreshes an active credential's catalog for an OperationRun. Preserves the
# saved state on transient failure and deactivates a confirmed invalid key.
class AiModelCatalogRefresh
  include AiModelDiscovery

  private

  def save_catalog(models)
    run.succeed! do |credential|
      credential.update!(available_models: models, models_refreshed_at: Time.current)
    end
  end

  def fail_discovery(error)
    run.fail! do |credential|
      run.update!(context: run.context.merge(error.details))
      credential.deactivate!(last_error: error.message) if error.invalid_key?
    end
  end
end
