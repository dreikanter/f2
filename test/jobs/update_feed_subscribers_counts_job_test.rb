require "test_helper"

class UpdateFeedSubscribersCountsJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def token_with_scopes(scopes)
    create(:access_token, :active, user: user, scopes: scopes)
  end

  def enqueued_feeds
    enqueued_jobs
      .select { |job| job["job_class"] == "UpdateFeedSubscribersCountJob" }
      .map { |job| ActiveJob::Arguments.deserialize(job["arguments"]).first }
  end

  test "#perform should enqueue a job per eligible feed" do
    feed = create(:feed, :enabled, user: user, access_token: token_with_scopes(AccessToken::TOKEN_SCOPES))

    UpdateFeedSubscribersCountsJob.perform_now

    assert_equal [feed], enqueued_feeds
  end

  test "#perform should enqueue feeds on a token with unknown scopes" do
    feed = create(:feed, :enabled, user: user, access_token: token_with_scopes(nil))

    UpdateFeedSubscribersCountsJob.perform_now

    assert_equal [feed], enqueued_feeds
  end

  test "#perform should skip feeds on a token without read-users-info" do
    create(:feed, :enabled, user: user, access_token: token_with_scopes(["read-my-info", "manage-posts"]))

    UpdateFeedSubscribersCountsJob.perform_now

    assert_empty enqueued_feeds
  end

  test "#perform should skip feeds that are not enabled" do
    create(:feed, :disabled, user: user, access_token: token_with_scopes(AccessToken::TOKEN_SCOPES))

    UpdateFeedSubscribersCountsJob.perform_now

    assert_empty enqueued_feeds
  end

  test "#perform should skip draft feeds" do
    create(:feed, :draft, user: user, access_token: token_with_scopes(AccessToken::TOKEN_SCOPES))

    UpdateFeedSubscribersCountsJob.perform_now

    assert_empty enqueued_feeds
  end
end
