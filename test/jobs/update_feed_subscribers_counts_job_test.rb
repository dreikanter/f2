require "test_helper"

class UpdateFeedSubscribersCountsJobTest < ActiveJob::TestCase
  test "enqueues one job for each eligible feed" do
    eligible = create(:feed, :enabled)
    create(:feed, :disabled)

    assert_enqueued_jobs 1, only: UpdateFeedSubscribersCountJob do
      UpdateFeedSubscribersCountsJob.perform_now
    end

    assert_enqueued_with(job: UpdateFeedSubscribersCountJob, args: [eligible])
  end
end
