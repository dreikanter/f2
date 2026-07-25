require "test_helper"

class UpdateFeedSubscribersCountsJobTest < ActiveJob::TestCase
  test "enqueues one job for each eligible feed" do
    eligible = create(:feed, :enabled)
    create(:feed, :disabled)
    create(:feed, :enabled, :without_access_token)
    create(:feed, :enabled, target_group: nil)

    assert_enqueued_jobs 1, only: UpdateFeedSubscribersCountJob do
      UpdateFeedSubscribersCountsJob.perform_now
    end

    assert_enqueued_with(job: UpdateFeedSubscribersCountJob, args: [eligible])
  end
end
