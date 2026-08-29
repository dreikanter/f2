require "test_helper"

class FeedIdentificationTimeoutJobTest < ActiveJob::TestCase
  test "#queue_name should use the dedicated timeout queue" do
    assert_equal "timeouts", FeedIdentificationTimeoutJob.queue_name
  end

  test "#perform should time out the matching processing run and rotate its run_id" do
    run_id = SecureRandom.uuid
    identification = create(:feed_identification, status: :processing, started_at: Time.current, run_id: run_id)

    FeedIdentificationTimeoutJob.perform_now(identification.id, run_id)

    assert_predicate identification.reload, :timed_out?
    refute_equal run_id, identification.run_id

    timed_out_attributes = identification.attributes.slice("status", "run_id", "updated_at")
    FeedIdentificationTimeoutJob.perform_now(identification.id, run_id)
    assert_equal timed_out_attributes, identification.reload.attributes.slice("status", "run_id", "updated_at")
  end

  test "#perform should do nothing for terminal runs" do
    identifications = %i[working unreachable no_feed timed_out].map do |status|
      create(:feed_identification, status: status, run_id: SecureRandom.uuid)
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
    current_run_id = SecureRandom.uuid
    identification = create(:feed_identification, status: :processing, started_at: Time.current,
                                                   run_id: current_run_id)
    original_attributes = identification.attributes.slice("status", "run_id", "updated_at")

    FeedIdentificationTimeoutJob.perform_now(identification.id, SecureRandom.uuid)

    assert_equal original_attributes, identification.reload.attributes.slice("status", "run_id", "updated_at")
  end

  test "#perform should not affect a restarted identification" do
    old_run_id = SecureRandom.uuid
    new_run_id = SecureRandom.uuid
    identification = create(:feed_identification, status: :processing, started_at: 1.minute.ago, run_id: old_run_id)

    SecureRandom.stub(:uuid, new_run_id) { identification.restart_detection }
    restarted_attributes = identification.reload.attributes.slice("status", "run_id", "started_at", "updated_at")

    FeedIdentificationTimeoutJob.perform_now(identification.id, old_run_id)

    assert_equal restarted_attributes,
                 identification.reload.attributes.slice("status", "run_id", "started_at", "updated_at")
  end

  test "#perform should do nothing when the identification was deleted" do
    run_id = SecureRandom.uuid
    identification = create(:feed_identification, status: :processing, started_at: Time.current, run_id: run_id)
    identification.destroy!

    assert_nothing_raised { FeedIdentificationTimeoutJob.perform_now(identification.id, run_id) }
  end
end
