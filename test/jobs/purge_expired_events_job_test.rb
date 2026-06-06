require "test_helper"

class PurgeExpiredEventsJobTest < ActiveJob::TestCase
  test "#perform should delete expired events" do
    expired = create(:event, expires_at: 1.hour.ago)
    active = create(:event, expires_at: 1.hour.from_now)
    permanent = create(:event)

    deleted_count = PurgeExpiredEventsJob.perform_now

    assert_equal 1, deleted_count
    assert_not Event.exists?(expired.id)
    assert Event.exists?(active.id)
    assert Event.exists?(permanent.id)
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
