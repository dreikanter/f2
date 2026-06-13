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

  test ".perform_now should reserve one delete per post" do
    create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    create(:post, feed: feed, freefeed_post_id: "post2", status: :withdrawn)
    subject = access_token.rate_limit_subject

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    freeze_time do
      GroupPurgeJob.perform_now(feed.id)

      capacity = RateLimit.capacity(:freefeed, :delete)
      assert_equal capacity - 2, freefeed_tokens_left(subject, :delete),
        "two withdrawals must spend exactly two delete tokens"
    end
  end

  test ".perform_now should reschedule itself when throttled" do
    create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    subject = access_token.rate_limit_subject

    freeze_time do
      drain_freefeed(subject, :delete, remaining: 0)

      assert_enqueued_with(job: GroupPurgeJob, args: [feed.id]) do
        GroupPurgeJob.perform_now(feed.id)
      end
    end

    assert_not_requested :delete, "#{access_token.host}/v4/posts/post1"
  end

  test ".perform_now should keep progress and reschedule the rest when throttled mid-batch" do
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    post2 = create(:post, feed: feed, freefeed_post_id: "post2", status: :withdrawn)
    subject = access_token.rate_limit_subject

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)

    freeze_time do
      # One delete token: the first withdrawal spends it, the second throttles.
      drain_freefeed(subject, :delete, remaining: 1)

      assert_enqueued_with(job: GroupPurgeJob, args: [feed.id]) do
        GroupPurgeJob.perform_now(feed.id)
      end
    end

    assert_nil post1.reload.freefeed_post_id
    assert_equal "post2", post2.reload.freefeed_post_id
  end

  test ".perform_now should reschedule without failing when FreeFeed throttles a DELETE" do
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    stub_request(:delete, "#{access_token.host}/v4/posts/post1")
      .to_return(status: 429, headers: { "Retry-After" => "30" })

    reported = []
    assert_enqueued_with(job: GroupPurgeJob, args: [feed.id]) do
      Rails.error.stub(:report, ->(*args, **) { reported << args }) do
        GroupPurgeJob.perform_now(feed.id)
      end
    end

    assert_empty reported, "a handled mid-batch throttle must not be reported as a fault"
    assert_equal "post1", post1.reload.freefeed_post_id, "a throttled DELETE must leave the post untouched"
  end

  test ".perform_now should report and stop when throttle retries are exhausted" do
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    subject = access_token.rate_limit_subject
    job = GroupPurgeJob.new(feed.id)
    job.executions = RateLimited::MAX_ATTEMPTS

    reported = []
    freeze_time do
      drain_freefeed(subject, :delete, remaining: 0)

      Rails.error.stub(:report, ->(error, **) { reported << error }) do
        assert_no_enqueued_jobs(only: GroupPurgeJob) { job.perform_now }
      end
    end

    assert_equal 1, reported.size
    assert_instance_of RateLimit::Throttled, reported.first
    assert_equal "post1", post1.reload.freefeed_post_id, "nothing is deleted when out of capacity"
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
