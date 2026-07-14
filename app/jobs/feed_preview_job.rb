# Runs FeedPreviewWorkflow for a persisted FeedPreview, under its current run_id.
class FeedPreviewJob < ApplicationJob
  queue_as :default

  # @param feed_preview_id [String] UUID of the FeedPreview
  # @param run_id [String] the run token captured when this job was enqueued
  # @param search_credential_id [String, nil] credential selected for this run
  def perform(feed_preview_id, run_id, search_credential_id = nil)
    feed_preview = FeedPreview.find_by(id: feed_preview_id)
    return unless feed_preview

    search_credential = feed_preview.user.search_credentials.active.find_by(id: search_credential_id)
    FeedPreviewWorkflow.new(feed_preview, run_id: run_id, search_credential: search_credential).execute
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
