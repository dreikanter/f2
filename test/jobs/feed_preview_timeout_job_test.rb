require "test_helper"

class FeedPreviewTimeoutJobTest < ActiveJob::TestCase
  test "#perform should fail the matching active run and rotate its run_id" do
    preview = create(:feed_preview, :processing, run_id: "run-1")

    FeedPreviewTimeoutJob.perform_now(preview.id, "run-1")

    assert preview.reload.failed?
    refute_equal "run-1", preview.run_id

    timed_out_attributes = preview.attributes.slice("status", "run_id", "updated_at")
    FeedPreviewTimeoutJob.perform_now(preview.id, "run-1")
    assert_equal timed_out_attributes, preview.reload.attributes.slice("status", "run_id", "updated_at")
  end

  test "#perform should fail a matching pending run" do
    preview = create(:feed_preview, status: :pending, run_id: "run-1")

    FeedPreviewTimeoutJob.perform_now(preview.id, "run-1")

    assert preview.reload.failed?
  end

  test "#perform should do nothing for terminal previews" do
    previews = [
      create(:feed_preview, :completed, run_id: "ready-run"),
      create(:feed_preview, :failed, run_id: "failed-run")
    ]
    original_attributes = previews.to_h do |preview|
      [preview.id, preview.attributes.slice("status", "run_id", "updated_at")]
    end

    previews.each { |preview| FeedPreviewTimeoutJob.perform_now(preview.id, preview.run_id) }

    previews.each do |preview|
      assert_equal original_attributes.fetch(preview.id),
                   preview.reload.attributes.slice("status", "run_id", "updated_at")
    end
  end

  test "#perform should do nothing when run_id has changed" do
    preview = create(:feed_preview, :processing, run_id: "run-2")
    original_attributes = preview.attributes.slice("status", "run_id", "updated_at")

    FeedPreviewTimeoutJob.perform_now(preview.id, "run-1")

    assert_equal original_attributes, preview.reload.attributes.slice("status", "run_id", "updated_at")
  end

  test "#perform should do nothing when the preview was deleted" do
    preview = create(:feed_preview, run_id: "run-1")
    preview.destroy!

    assert_nothing_raised { FeedPreviewTimeoutJob.perform_now(preview.id, "run-1") }
  end
end
