class ProviderCredentialValidationTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param run [OperationRun] validation being timed out
  def perform(run)
    run.timeout_credential_validation!
  end
end
