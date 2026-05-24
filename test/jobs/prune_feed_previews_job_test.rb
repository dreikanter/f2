require "test_helper"

class PruneFeedPreviewsJobTest < ActiveJob::TestCase
  test "#perform should delete previews older than the retention window" do
    old = create(:feed_preview, created_at: 8.days.ago)
    recent = create(:feed_preview, created_at: 1.hour.ago)

    PruneFeedPreviewsJob.perform_now

    assert_not FeedPreview.exists?(old.id)
    assert FeedPreview.exists?(recent.id)
  end
end
