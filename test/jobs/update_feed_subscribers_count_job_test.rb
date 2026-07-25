require "test_helper"

class UpdateFeedSubscribersCountJobTest < ActiveJob::TestCase
  test "updates subscriber count and timestamp" do
    feed = create(:feed, :enabled)
    response = {
      users: {
        username: feed.target_group,
        statistics: { subscribers: "42" }
      }
    }

    stub_request(:get, "#{feed.access_token.host}/v2/users/#{feed.target_group}")
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
end
