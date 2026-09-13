class AiCredentialValidationJob < ApplicationJob
  queue_as :default

  # @param run [OperationRun] validation being performed
  def perform(run)
    AiCredentialValidation.new(run).call
  end
end
