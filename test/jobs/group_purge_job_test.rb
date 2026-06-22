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

  test ".perform_now should delete FreeFeed posts and mark them withdrawn" do
    post1 = create(:post, :published, feed: feed, freefeed_post_id: "post1")
    post2 = create(:post, :published, feed: feed, freefeed_post_id: "post2")
    post3 = create(:post, feed: feed, freefeed_post_id: nil)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    GroupPurgeJob.perform_now(feed.id)

    assert_nil post1.reload.freefeed_post_id
    assert_predicate post1.reload, :withdrawn?
    assert_nil post2.reload.freefeed_post_id
    assert_predicate post2.reload, :withdrawn?
    assert_not_predicate post3.reload, :withdrawn?, "posts without a FreeFeed ID are not touched"
  end

  test ".perform_now should recompute published metrics for affected dates" do
    post1 = create(:post, :published, feed: feed, freefeed_post_id: "post1")
    metric = create(:feed_metric, :with_published_posts, feed: feed, date: post1.reposted_at.to_date)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)

    GroupPurgeJob.perform_now(feed.id)

    assert_equal 0, metric.reload.published_posts_count
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

  test ".perform_now should sleep and continue instead of rescheduling when throttled" do
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)

    # Simulate one denied acquire followed by an allowed one.
    acquire_call = 0
    acquire_stub = ->(*args, **kwargs) {
      acquire_call += 1
      acquire_call == 1 ? RateLimit::Result.new(allowed: false, retry_after: 5.0)
                        : RateLimit::Result.new(allowed: true, retry_after: 0.0)
    }

    slept = []
    job = GroupPurgeJob.new(feed.id)

    RateLimit.stub(:acquire, acquire_stub) do
      job.stub(:sleep, ->(n) { slept << n }) do
        assert_no_enqueued_jobs(only: GroupPurgeJob) do
          job.perform_now
        end
      end
    end

    assert_equal [5.0], slept, "should sleep for the retry_after period"
    assert_nil post1.reload.freefeed_post_id, "post should be deleted after sleeping for capacity"
  end

  test ".perform_now should sleep and retry instead of rescheduling when FreeFeed throttles a DELETE" do
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    stub_request(:delete, "#{access_token.host}/v4/posts/post1")
      .to_return(status: 429, headers: { "Retry-After" => "30" })
      .then.to_return(status: 200)

    slept = []
    reported = []
    job = GroupPurgeJob.new(feed.id)

    # Advance time inside sleep so the penalty block expires before the retry acquire.
    job.stub(:sleep, ->(n) { slept << n; travel(n.ceil.seconds + 1) }) do
      Rails.error.stub(:report, ->(*args, **) { reported << args }) do
        assert_no_enqueued_jobs(only: GroupPurgeJob) do
          job.perform_now
        end
      end
    end

    assert_empty reported, "throttling must not be reported as a fault"
    assert_not_empty slept, "should sleep when FreeFeed throttles a DELETE"
    assert_nil post1.reload.freefeed_post_id, "post should be deleted after sleeping and retrying"
  end

  test ".perform_now should continue on error and log failure" do
    post1 = create(:post, :published, feed: feed, freefeed_post_id: "post1")
    post2 = create(:post, :published, feed: feed, freefeed_post_id: "post2")

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 500)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    GroupPurgeJob.perform_now(feed.id)

    assert_equal "post1", post1.reload.freefeed_post_id
    assert_predicate post1.reload, :published?, "status unchanged when DELETE fails"
    assert_nil post2.reload.freefeed_post_id
    assert_predicate post2.reload, :withdrawn?
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
