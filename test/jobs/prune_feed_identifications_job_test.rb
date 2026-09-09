require "test_helper"

class PruneFeedIdentificationsJobTest < ActiveJob::TestCase
  test "#perform should delete results from obsolete and unknown configurations" do
    obsolete = create(:feed_identification, :working, configuration_digest: "previous configuration")
    legacy = create(:feed_identification, :working, configuration_digest: nil)
    current = create(:feed_identification, :working)

    PruneFeedIdentificationsJob.perform_now

    assert_not FeedIdentification.exists?(obsolete.id)
    assert_not FeedIdentification.exists?(legacy.id)
    assert FeedIdentification.exists?(current.id)
  end

  test "#perform should delete old results and preserve recently restarted checks" do
    stale = create(:feed_identification, :working, created_at: 8.days.ago, updated_at: 8.days.ago)
    restarted = create(:feed_identification, :working, created_at: 8.days.ago, updated_at: 8.days.ago)
    restarted.restart_detection

    PruneFeedIdentificationsJob.perform_now

    assert_not FeedIdentification.exists?(stale.id)
    assert FeedIdentification.exists?(restarted.id)
  end
end
