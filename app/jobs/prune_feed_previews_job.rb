# Removes stale preview rows. Ready previews are only reused within
# Feed::PREVIEW_FRESHNESS_WINDOW, so anything older than RETENTION is safe to drop.
class PruneFeedPreviewsJob < ApplicationJob
  queue_as :default

  RETENTION = 7.days

  def perform
    FeedPreview.where(created_at: ..RETENTION.ago).in_batches(of: 500).delete_all
  end
end
