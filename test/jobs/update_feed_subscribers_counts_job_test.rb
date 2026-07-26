require "test_helper"

class UpdateFeedSubscribersCountsJobTest < ActiveJob::TestCase
  test "enqueues jobs for eligible feeds only" do
    eligible = create(:feed, :enabled)
    disabled = create(:feed, :disabled)
    enqueued_feeds = []

    UpdateFeedSubscribersCountJob.stub(:perform_later, ->(feed) { enqueued_feeds << feed }) do
      UpdateFeedSubscribersCountsJob.perform_now
    end

    assert_includes enqueued_feeds, eligible
    refute_includes enqueued_feeds, disabled
  end
end
