require "test_helper"

class FeedPreviewTimeoutJobTest < ActiveJob::TestCase
  RUN_ID = "11111111-1111-4111-8111-111111111111"
  NEXT_RUN_ID = "22222222-2222-4222-8222-222222222222"
  READY_RUN_ID = "33333333-3333-4333-8333-333333333333"
  FAILED_RUN_ID = "44444444-4444-4444-8444-444444444444"

  test "#queue_name should use the dedicated timeout queue" do
    assert_equal "timeouts", FeedPreviewTimeoutJob.queue_name
  end

  test "#perform should fail the matching active run and rotate its run_id" do
    preview = create(:feed_preview, :processing, run_id: RUN_ID)

    FeedPreviewTimeoutJob.perform_now(preview.id, RUN_ID)

    assert preview.reload.failed?
    refute_equal RUN_ID, preview.run_id

    timed_out_attributes = preview.attributes.slice("status", "run_id", "updated_at")
    FeedPreviewTimeoutJob.perform_now(preview.id, RUN_ID)
    assert_equal timed_out_attributes, preview.reload.attributes.slice("status", "run_id", "updated_at")
  end

  test "#perform should fail a matching pending run" do
    preview = create(:feed_preview, status: :pending, run_id: RUN_ID)

    FeedPreviewTimeoutJob.perform_now(preview.id, RUN_ID)

    assert preview.reload.failed?
  end

  test "#perform should do nothing for terminal previews" do
    previews = [
      create(:feed_preview, :completed, run_id: READY_RUN_ID),
      create(:feed_preview, :failed, run_id: FAILED_RUN_ID)
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
    preview = create(:feed_preview, :processing, run_id: NEXT_RUN_ID)
    original_attributes = preview.attributes.slice("status", "run_id", "updated_at")

    FeedPreviewTimeoutJob.perform_now(preview.id, RUN_ID)

    assert_equal original_attributes, preview.reload.attributes.slice("status", "run_id", "updated_at")
  end

  test "#perform should do nothing when the preview was deleted" do
    preview = create(:feed_preview, run_id: RUN_ID)
    preview.destroy!

    assert_nothing_raised { FeedPreviewTimeoutJob.perform_now(preview.id, RUN_ID) }
  end
end
