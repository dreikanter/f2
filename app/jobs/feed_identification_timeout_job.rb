class FeedIdentificationTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param feed_identification_id [String] UUID of the FeedIdentification
  # @param run_id [String] run token captured when this job was enqueued
  def perform(feed_identification_id, run_id)
    FeedIdentification.find_by(id: feed_identification_id)&.timeout!(run_id: run_id)
  end
end
