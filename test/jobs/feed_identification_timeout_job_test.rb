require "test_helper"

class FeedIdentificationTimeoutJobTest < ActiveJob::TestCase
  test "should use the dedicated timeout queue" do
    assert_equal "timeouts", FeedIdentificationTimeoutJob.queue_name
  end

  test "#perform should time out the matching processing run and rotate its run_id" do
    identification = create(:feed_identification, status: :processing, started_at: Time.current, run_id: "run-1")

    FeedIdentificationTimeoutJob.perform_now(identification.id, "run-1")

    assert_predicate identification.reload, :timed_out?
    refute_equal "run-1", identification.run_id

    timed_out_attributes = identification.attributes.slice("status", "run_id", "updated_at")
    FeedIdentificationTimeoutJob.perform_now(identification.id, "run-1")
    assert_equal timed_out_attributes, identification.reload.attributes.slice("status", "run_id", "updated_at")
  end

  test "#perform should do nothing for terminal runs" do
    identifications = %i[working unreachable no_feed timed_out].map do |status|
      create(:feed_identification, status: status, run_id: "#{status}-run")
    end
    original_attributes = identifications.to_h do |identification|
      [identification.id, identification.attributes.slice("status", "run_id", "updated_at")]
    end

    identifications.each do |identification|
      FeedIdentificationTimeoutJob.perform_now(identification.id, identification.run_id)
    end

    identifications.each do |identification|
      assert_equal original_attributes.fetch(identification.id),
                   identification.reload.attributes.slice("status", "run_id", "updated_at")
    end
  end

  test "#perform should do nothing when the run was superseded" do
    identification = create(:feed_identification, status: :processing, started_at: Time.current, run_id: "run-2")
    original_attributes = identification.attributes.slice("status", "run_id", "updated_at")

    FeedIdentificationTimeoutJob.perform_now(identification.id, "run-1")

    assert_equal original_attributes, identification.reload.attributes.slice("status", "run_id", "updated_at")
  end

  test "#perform should not affect a restarted identification" do
    identification = create(:feed_identification, status: :processing, started_at: 1.minute.ago, run_id: "run-1")

    SecureRandom.stub(:uuid, "run-2") { identification.restart_detection }
    restarted_attributes = identification.reload.attributes.slice("status", "run_id", "started_at", "updated_at")

    FeedIdentificationTimeoutJob.perform_now(identification.id, "run-1")

    assert_equal restarted_attributes,
                 identification.reload.attributes.slice("status", "run_id", "started_at", "updated_at")
  end

  test "#perform should do nothing when the identification was deleted" do
    identification = create(:feed_identification, status: :processing, started_at: Time.current, run_id: "run-1")
    identification.destroy!

    assert_nothing_raised { FeedIdentificationTimeoutJob.perform_now(identification.id, "run-1") }
  end
end
