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
end
