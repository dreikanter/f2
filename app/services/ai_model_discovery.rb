# Shared execution for validation and catalog refresh. Each operation supplies
# its own success and failure policy.
module AiModelDiscovery
  # @param run [OperationRun] validation or catalog refresh being performed
  def initialize(run)
    @run = run
  end

  def call
    return unless run.reload.running?
    return run.timeout! if run.deadline_reached?

    original_data = credential.credential_data.deep_dup
    models = AiModelCatalog.fetch(credential)

    with_current_credential(original_data) { save_catalog(models) }
  rescue LlmProvider::Error => error
    Rails.error.report(error, context: { credential_id: credential.id })
    with_current_credential(original_data) { fail_discovery(error) }
  end

  private

  attr_reader :run

  def credential
    run.subject
  end

  def with_current_credential(original_data)
    credential.with_lock do
      return run.supersede! unless credential.credential_data == original_data
      return run.supersede! if run.models_refresh? && !credential.active?
      return run.timeout! if run.deadline_reached?

      yield
    end
  end
end
