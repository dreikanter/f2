class ProviderCredentialValidationTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param run [OperationRun] validation being timed out
  def perform(run)
    run.timeout!
  end
end
