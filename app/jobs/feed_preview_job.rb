# Runs FeedPreviewWorkflow for a persisted FeedPreview, under its current run_id.
class FeedPreviewJob < ApplicationJob
  queue_as :default

  # @param feed_preview_id [String] UUID of the FeedPreview
  # @param run_id [String] the run token captured when this job was enqueued
  def perform(feed_preview_id, run_id)
    feed_preview = FeedPreview.find_by(id: feed_preview_id)
    return unless feed_preview

    FeedPreviewWorkflow.new(feed_preview, run_id: run_id).execute
  rescue LlmClient::CredentialMissing => e
    # AI profile previewed without an active credential. The workflow already
    # marked the preview failed; this is a user-state condition, not a crash.
    Rails.logger.info "FeedPreviewJob: no AI credential for preview #{feed_preview_id}: #{e.message}"
  rescue => e
    Rails.logger.error "FeedPreviewJob failed for preview #{feed_preview_id}: #{e.message}"
    raise
  end
end
