class FeedPreviewTimeoutJob < ApplicationJob
  queue_as :timeouts

  # @param feed_preview_id [String] UUID of the FeedPreview
  # @param run_id [String] the run token captured when this job was enqueued
  def perform(feed_preview_id, run_id)
    FeedPreview.find_by(id: feed_preview_id)&.timeout!(run_id: run_id)
  end
end
