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

  test "reschedules when FreeFeed responds with 429" do
    feed = create(:feed, :enabled)
    stub_request(:get, "#{feed.access_token.host}/v2/users/#{feed.target_group}/statistics")
      .to_return(status: 429, headers: { "Retry-After" => "30" })

    assert_enqueued_with(job: UpdateFeedSubscribersCountJob) do
      UpdateFeedSubscribersCountJob.perform_now(feed)
    end
  end
end
