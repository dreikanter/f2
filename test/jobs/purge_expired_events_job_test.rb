require "test_helper"

class PurgeExpiredEventsJobTest < ActiveJob::TestCase
  test "#perform should delete expired events" do
    expired = create(:event, expires_at: 1.hour.ago)
    active = create(:event, expires_at: 1.hour.from_now)
    recent = create(:event)

    deleted_count = PurgeExpiredEventsJob.perform_now

    assert_equal 1, deleted_count
    assert_not Event.exists?(expired.id)
    assert Event.exists?(active.id)
    assert Event.exists?(recent.id)
  end

  test "#perform should delete unexpiring events older than the default retention" do
    stale = create(:event, expires_at: nil, created_at: (Event::DEFAULT_RETENTION + 1.day).ago)
    recent = create(:event, expires_at: nil, created_at: 1.day.ago)

    deleted_count = PurgeExpiredEventsJob.perform_now

    assert_equal 1, deleted_count
    assert_not Event.exists?(stale.id)
    assert Event.exists?(recent.id)
  end

  test "#perform should record a completion event for its JobRun" do
    create(:event, expires_at: 1.hour.ago)
    job = PurgeExpiredEventsJob.new
    run = create(:job_run, job_class: "PurgeExpiredEventsJob", job_id: job.job_id)

    job.perform_now

    event = run.events.find_by(type: "job.purge_expired_events.completed")
    assert_not_nil event
    assert_equal 1, event.metadata["deleted_count"]
  end

  test "#perform should delete references of purged events" do
    expired = create(:event, expires_at: 1.hour.ago)
    active = create(:event, expires_at: 1.hour.from_now)
    expired_reference = create(:event_reference, event: expired)
    active_reference = create(:event_reference, event: active)

    PurgeExpiredEventsJob.perform_now

    assert_not EventReference.exists?(expired_reference.id)
    assert EventReference.exists?(active_reference.id)
  end
end
