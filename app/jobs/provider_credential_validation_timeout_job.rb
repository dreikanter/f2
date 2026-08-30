class ProviderCredentialValidationTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param run [OperationRun] validation being timed out
  def perform(run)
    run.timeout! do |credential|
      credential.update!(state: run.context.fetch("fallback_state"))
    end
  end
end
