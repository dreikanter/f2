require "test_helper"

class PruneFeedPreviewsJobTest < ActiveJob::TestCase
  test "#perform should delete previews not updated within the retention window" do
    stale = create(:feed_preview, created_at: 8.days.ago, updated_at: 8.days.ago)
    restarted = create(:feed_preview, created_at: 8.days.ago, updated_at: 1.hour.ago)

    PruneFeedPreviewsJob.perform_now

    assert_not FeedPreview.exists?(stale.id)
    assert FeedPreview.exists?(restarted.id)
  end
end
