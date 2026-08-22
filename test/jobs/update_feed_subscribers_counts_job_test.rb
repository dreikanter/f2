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

  def enqueued_scope_reads
    enqueued_jobs
      .select { |job| job["job_class"] == "TokenScopesRefreshJob" }
      .map { |job| ActiveJob::Arguments.deserialize(job["arguments"]).first }
  end

  test "#perform should enqueue a job per eligible feed" do
    feed = create(:feed, :enabled, user: user, access_token: token_with_scopes(AccessToken::TOKEN_SCOPES))

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

  test "#perform should read the scopes of a token that never recorded them" do
    access_token = token_with_scopes([])
    create(:feed, :enabled, user: user, access_token: access_token)

    UpdateFeedSubscribersCountsJob.perform_now

    assert_equal [access_token], enqueued_scope_reads
    assert_empty enqueued_feeds
  end

  test "#perform should not read the scopes of a token that recorded them" do
    create(:feed, :enabled, user: user, access_token: token_with_scopes(["read-my-info", "manage-posts"]))

    UpdateFeedSubscribersCountsJob.perform_now

    assert_empty enqueued_scope_reads
  end

  test "#perform should not read scopes for a token with no feed to count" do
    token_with_scopes([])

    UpdateFeedSubscribersCountsJob.perform_now

    assert_empty enqueued_scope_reads
  end
end
