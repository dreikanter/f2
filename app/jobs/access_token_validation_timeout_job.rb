class AccessTokenValidationTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param access_token [AccessToken] token being validated
  # @param run_id [String] validation UUID captured when the run started
  def perform(access_token, run_id)
    access_token.timeout_validation!(run_id: run_id)
  end
end
