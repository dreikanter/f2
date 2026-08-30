class TokenGroupsRefreshTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param access_token_detail_id [String] UUID of the AccessTokenDetail
  # @param run_id [String] run token captured when this job was enqueued
  def perform(access_token_detail_id, run_id)
    AccessTokenDetail.find_by(id: access_token_detail_id)&.timeout_groups_refresh!(run_id: run_id)
  end
end
