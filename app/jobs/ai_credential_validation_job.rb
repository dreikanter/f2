class AiCredentialValidationJob < ApplicationJob
  queue_as :default

  # @param run [OperationRun] validation being performed
  def perform(run)
    run.fail! do |credential|
      credential.update!(state: run.context.fetch("fallback_state"),
                         last_error: AiModelCatalog::UNAVAILABLE_MESSAGE)
    end
  end
end
