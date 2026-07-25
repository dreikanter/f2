require "test_helper"

class UpdateFeedSubscribersCountsJobTest < ActiveJob::TestCase
  test "enqueues one job for each eligible feed" do
    eligible = create(:feed, :enabled)
    disabled = create(:feed, :disabled)
    without_token = create(:feed, :enabled, access_token: nil)
    without_target = create(:feed, :enabled, target_group: nil)

    assert_enqueued_jobs 1, only: UpdateFeedSubscribersCountJob do
      UpdateFeedSubscribersCountsJob.perform_now
    end

    assert_enqueued_with(job: UpdateFeedSubscribersCountJob, args: [eligible])
    assert_no_enqueued_jobs only: UpdateFeedSubscribersCountJob do
      disabled
      without_token
      without_target
    end
  end
end
