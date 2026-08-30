class TokenGroupsRefreshTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param run [OperationRun] groups refresh being timed out
  def perform(run)
    run.timeout!
  end
end
