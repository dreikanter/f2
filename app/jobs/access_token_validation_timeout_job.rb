class AccessTokenValidationTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param access_token_id [String] UUID of the AccessToken
  # @param run_id [String] validation UUID captured when the run started
  def perform(access_token_id, run_id)
    AccessToken.find_by(id: access_token_id)&.timeout_validation!(run_id: run_id)
  end
end
