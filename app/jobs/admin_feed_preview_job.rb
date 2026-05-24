class AdminFeedPreviewJob < ApplicationJob
  queue_as :default

  # @param feed_preview_id [String] UUID of the feed preview to generate
  def perform(feed_preview_id)
    feed_preview = FeedPreview.find_by(id: feed_preview_id)
    return unless feed_preview

    FeedPreviewWorkflow.new(feed_preview).execute
  rescue LlmClient::CredentialMissing => e
    # Expected when an AI profile is previewed without the user having an
    # active AI credential. The workflow already marked the preview failed;
    # this is a user-state condition, not an alert-worthy crash, so swallow
    # it instead of re-raising (no retries, no error reporting).
    Rails.logger.info "AdminFeedPreviewJob: no AI credential for preview #{feed_preview_id}: #{e.message}"
    feed_preview.update!(status: :failed)
  rescue => e
    Rails.logger.error "AdminFeedPreviewJob failed for preview #{feed_preview_id}: #{e.message}"

    feed_preview&.update!(status: :failed)
    raise
  end
end
