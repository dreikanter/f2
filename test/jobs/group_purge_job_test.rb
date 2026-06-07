require "test_helper"

class GroupPurgeJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed
    @feed ||= create(:feed, user: user, access_token: access_token, target_group: "testgroup")
  end

  test ".perform_now should withdraw all posts with freefeed_post_id from feed" do
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    post2 = create(:post, feed: feed, freefeed_post_id: "post2", status: :withdrawn)
    post3 = create(:post, feed: feed, freefeed_post_id: nil, status: :withdrawn)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    GroupPurgeJob.perform_now(feed.id)

    assert_nil post1.reload.freefeed_post_id
    assert_nil post2.reload.freefeed_post_id
    assert_nil post3.reload.freefeed_post_id
  end

  test ".perform_now should reserve a delete per post" do
    create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    create(:post, feed: feed, freefeed_post_id: "post2", status: :withdrawn)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    captured = []
    RateLimit.stub(:acquire!, lambda { |_policy, subject:, cost:|
      captured << [subject, cost]
    }) do
      GroupPurgeJob.perform_now(feed.id)
    end

    assert_equal [[access_token.rate_limit_subject, { delete: 1 }]] * 2, captured
  end

  test ".perform_now should re-enqueue itself for the feed when throttled" do
    create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)

    RateLimit.stub(:acquire!, ->(*, **) { raise RateLimit::Throttled.new(retry_after: 2) }) do
      assert_enqueued_with(job: GroupPurgeJob, args: [feed.id]) do
        GroupPurgeJob.perform_now(feed.id)
      end
    end

    assert_not_requested :delete, "#{access_token.host}/v4/posts/post1"
  end

  test ".perform_now should keep progress and reschedule the rest when throttled mid-batch" do
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    post2 = create(:post, feed: feed, freefeed_post_id: "post2", status: :withdrawn)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)

    calls = 0
    RateLimit.stub(:acquire!, lambda { |*, **|
      calls += 1
      raise RateLimit::Throttled.new(retry_after: 5) if calls > 1
    }) do
      assert_enqueued_with(job: GroupPurgeJob, args: [feed.id]) do
        GroupPurgeJob.perform_now(feed.id)
      end
    end

    assert_nil post1.reload.freefeed_post_id
    assert_equal "post2", post2.reload.freefeed_post_id
  end

  test ".perform_now should continue on error and log failure" do
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    post2 = create(:post, feed: feed, freefeed_post_id: "post2", status: :withdrawn)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 500)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    GroupPurgeJob.perform_now(feed.id)

    assert_equal "post1", post1.reload.freefeed_post_id
    assert_nil post2.reload.freefeed_post_id
  end

  test ".perform_now should exit gracefully if feed not found" do
    assert_nothing_raised do
      GroupPurgeJob.perform_now(999999)
    end
  end

  test ".perform_now should process posts for specified feed only" do
    other_feed = create(:feed, user: user, access_token: access_token, target_group: "othergroup")
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    post2 = create(:post, feed: other_feed, freefeed_post_id: "post2", status: :withdrawn)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)

    GroupPurgeJob.perform_now(feed.id)

    assert_nil post1.reload.freefeed_post_id
    assert_equal "post2", post2.reload.freefeed_post_id
  end
end
