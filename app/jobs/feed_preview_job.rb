class FeedPreviewJob < ApplicationJob
  queue_as :default

  # @param feed_preview_id [String] UUID of the feed preview to generate
  def perform(feed_preview_id)
    feed_preview = FeedPreview.find_by(id: feed_preview_id)
    return unless feed_preview

    FeedPreviewWorkflow.new(feed_preview).execute
  rescue => e
    Rails.logger.error "FeedPreviewJob failed for preview #{feed_preview_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    feed_preview&.update!(status: :failed)
    raise
  end
end
