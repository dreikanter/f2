require "test_helper"

class PruneSessionsJobTest < ActiveJob::TestCase
  test "#perform should delete expired sessions and preserve user activity" do
    freeze_time do
      expired = create(:session, last_seen_at: Session::INACTIVITY_TIMEOUT.ago - 1.second)
      boundary = create(:session, last_seen_at: Session::INACTIVITY_TIMEOUT.ago)
      active = create(:session, created_at: 90.days.ago, last_seen_at: 1.minute.ago)

      PruneSessionsJob.perform_now

      assert_not Session.exists?(expired.id)
      assert Session.exists?(boundary.id)
      assert Session.exists?(active.id)
      assert_equal expired.last_seen_at, expired.user.reload.last_seen_at
    end
  end
end
