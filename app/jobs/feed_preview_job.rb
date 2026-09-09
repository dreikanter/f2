# Runs FeedPreviewWorkflow for a persisted FeedPreview, under its current run_id.
class FeedPreviewJob < ApplicationJob
  queue_as :default

  # @param feed_preview_id [String] UUID of the FeedPreview
  # @param run_id [String] the run token captured when this job was enqueued
  # @param params_digest [String, nil] expected identity, absent in previously queued jobs
  def perform(feed_preview_id, run_id, params_digest = nil)
    feed_preview = FeedPreview.find_by(id: feed_preview_id)
    return unless feed_preview
    return if params_digest && params_digest != feed_preview.params_digest

    FeedPreviewWorkflow.new(feed_preview, run_id: run_id).execute
  rescue LlmClient::CredentialMissing => e
    # AI profile previewed without one of its required active credentials. The
    # workflow already marked the preview failed; this is user state, not a crash.
    Rails.logger.info "FeedPreviewJob: missing credential for preview #{feed_preview_id}: #{e.message}"
  rescue => e
    # The workflow already transitioned the preview to :failed. Do not re-raise:
    # retrying would reset status back to :processing (via initialize_workflow),
    # causing the status to oscillate and leaving the client polling indefinitely.
    Rails.logger.error "FeedPreviewJob failed for preview #{feed_preview_id}: #{e.message}"
    Rails.error.report(e, context: { feed_preview_id: feed_preview_id })
  end
end
