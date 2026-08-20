require "test_helper"

class UpdateFeedSubscribersCountJobTest < ActiveJob::TestCase
  test "updates subscriber count and timestamp" do
    feed = create(:feed, :enabled)
    response = {
      users: { username: feed.target_group },
      statistics: { subscribers: "42" }
    }

    stub_request(:get, "#{feed.access_token.host}/v2/users/#{feed.target_group}/statistics")
      .to_return(status: 200, body: response.to_json, headers: { "Content-Type" => "application/json" })

    freeze_time do
      UpdateFeedSubscribersCountJob.perform_now(feed)

      feed.reload
      assert_equal 42, feed.subscribers_count
      assert_equal Time.current, feed.subscribers_count_updated_at
    end
  end

  test "does nothing for a disabled feed" do
    feed = create(:feed, :disabled)

    UpdateFeedSubscribersCountJob.perform_now(feed)

    assert_nil feed.reload.subscribers_count
    assert_not_requested :get, /\/v2\/users\//
  end

  test "does nothing for an inactive access token" do
    feed = create(:feed, :enabled)
    feed.access_token.inactive!

    UpdateFeedSubscribersCountJob.perform_now(feed)

    assert_nil feed.reload.subscribers_count
    assert_not_requested :get, /\/v2\/users\//
  end

  test "reschedules when the local rate limit is exhausted" do
    feed = create(:feed, :enabled)
    drain_freefeed(feed.access_token.rate_limit_subject, :get, remaining: 0)

    assert_enqueued_with(job: UpdateFeedSubscribersCountJob) do
      UpdateFeedSubscribersCountJob.perform_now(feed)
    end

    assert_not_requested :get, /\/v2\/users\//
  end

  test "#perform should keep the stale count when the token has no access to statistics" do
    feed = feed_with_stale_count
    stub_statistics_error(feed, status: 401, err: "token has no access to this API method")

    assert_nothing_raised do
      UpdateFeedSubscribersCountJob.perform_now(feed)
    end

    assert_skipped_without_fallout(feed)
  end

  test "#perform should keep the stale count when FreeFeed forbids reading statistics" do
    feed = feed_with_stale_count
    stub_statistics_error(feed, status: 403, err: "You cannot see this user's statistics")

    assert_nothing_raised do
      UpdateFeedSubscribersCountJob.perform_now(feed)
    end

    assert_skipped_without_fallout(feed)
  end

  test "#perform should keep the stale count when the target group is not found" do
    feed = feed_with_stale_count
    stub_statistics_error(feed, status: 404, err: "Account 'testgroup' was not found")

    assert_nothing_raised do
      UpdateFeedSubscribersCountJob.perform_now(feed)
    end

    assert_skipped_without_fallout(feed)
  end

  test "#perform should send a dead token to validation" do
    feed = feed_with_stale_count
    stub_statistics_error(feed, status: 401, err: "inactive or expired token")

    assert_enqueued_with(job: TokenValidationJob, args: [feed.access_token]) do
      UpdateFeedSubscribersCountJob.perform_now(feed)
    end

    assert_equal 7, feed.reload.subscribers_count
    # The status must not change until validation actually runs, or queued
    # publications would fail against a transiently non-active token.
    assert feed.access_token.reload.active?
  end

  test "reschedules when FreeFeed responds with 429" do
    feed = create(:feed, :enabled)
    stub_request(:get, "#{feed.access_token.host}/v2/users/#{feed.target_group}/statistics")
      .to_return(status: 429, headers: { "Retry-After" => "30" })

    assert_enqueued_with(job: UpdateFeedSubscribersCountJob) do
      UpdateFeedSubscribersCountJob.perform_now(feed)
    end
  end

  private

  def feed_with_stale_count
    create(:feed, :enabled).tap do |feed|
      feed.update!(subscribers_count: 7, subscribers_count_updated_at: Time.parse("2026-08-19 03:00:00 UTC"))
    end
  end

  def stub_statistics_error(feed, status:, err:)
    stub_request(:get, "#{feed.access_token.host}/v2/users/#{feed.target_group}/statistics")
      .to_return(status: status, body: { err: err }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def assert_skipped_without_fallout(feed)
    feed.reload
    assert_equal 7, feed.subscribers_count
    assert_equal Time.parse("2026-08-19 03:00:00 UTC"), feed.subscribers_count_updated_at
    assert feed.enabled?
    assert feed.access_token.reload.active?
    assert_no_enqueued_jobs
  end
end
