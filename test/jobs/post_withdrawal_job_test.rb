require "test_helper"

class PostWithdrawalJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed
    @feed ||= create(:feed, user: user, access_token: access_token)
  end

  test ".perform_now should reserve a delete and reschedule when throttled" do
    post = create(:post, :published, feed: feed, freefeed_post_id: "test_post_123")

    subject = access_token.rate_limit_subject

    freeze_time do
      drain_freefeed(subject, :delete, remaining: 0)

      assert_enqueued_with(job: PostWithdrawalJob) do
        PostWithdrawalJob.perform_now(feed.id, "test_post_123", post.id)
      end
    end

    assert_not_requested :delete, "#{access_token.host}/v4/posts/test_post_123"
  end

  test ".perform_now should reschedule without failing when the DELETE is throttled mid-call" do
    post = create(:post, :published, feed: feed, freefeed_post_id: "test_post_123")
    stub_request(:delete, "#{access_token.host}/v4/posts/test_post_123")
      .to_return(status: 429, headers: { "Retry-After" => "30" })

    reported = []
    assert_enqueued_with(job: PostWithdrawalJob) do
      Rails.error.stub(:report, ->(*args, **) { reported << args }) do
        PostWithdrawalJob.perform_now(feed.id, "test_post_123", post.id)
      end
    end

    assert_empty reported, "a handled throttle must not be reported as a fault"
    assert_equal "test_post_123", post.reload.freefeed_post_id, "the post id must survive a throttled withdrawal"
  end

  test ".perform_now should report and stop when throttle retries are exhausted" do
    post = create(:post, :published, feed: feed, freefeed_post_id: "test_post_123")
    subject = access_token.rate_limit_subject
    job = PostWithdrawalJob.new(feed.id, "test_post_123", post.id)
    job.executions = RateLimited::MAX_ATTEMPTS

    reported = []
    freeze_time do
      drain_freefeed(subject, :delete, remaining: 0)

      Rails.error.stub(:report, ->(error, **) { reported << error }) do
        assert_no_enqueued_jobs(only: PostWithdrawalJob) { job.perform_now }
      end
    end

    assert_equal 1, reported.size
    assert_instance_of RateLimit::Throttled, reported.first
    assert_equal "test_post_123", post.reload.freefeed_post_id
  end

  test ".perform_now should delete post from FreeFeed" do
    stub_request(:delete, "#{access_token.host}/v4/posts/test_post_123")
      .to_return(status: 200)

    PostWithdrawalJob.perform_now(feed.id, "test_post_123")

    assert_requested :delete, "#{access_token.host}/v4/posts/test_post_123"
  end

  test ".perform_now should drop the FreeFeed post id after deletion" do
    post = create(:post, :published, feed: feed, freefeed_post_id: "test_post_123")
    stub_request(:delete, "#{access_token.host}/v4/posts/test_post_123")
      .to_return(status: 200)

    PostWithdrawalJob.perform_now(feed.id, "test_post_123", post.id)

    assert_nil post.reload.freefeed_post_id
  end

  test ".perform_now should keep the FreeFeed post id when deletion fails" do
    post = create(:post, :published, feed: feed, freefeed_post_id: "test_post_123")
    stub_request(:delete, "#{access_token.host}/v4/posts/test_post_123")
      .to_return(status: 500, body: "Internal Server Error")

    PostWithdrawalJob.perform_now(feed.id, "test_post_123", post.id)

    assert_equal "test_post_123", post.reload.freefeed_post_id
  end

  test ".perform_now should handle FreeFeed API errors gracefully" do
    stub_request(:delete, "#{access_token.host}/v4/posts/test_post_123")
      .to_return(status: 500, body: "Internal Server Error")

    assert_nothing_raised do
      PostWithdrawalJob.perform_now(feed.id, "test_post_123")
    end
  end

  test ".perform_now should handle missing feed gracefully" do
    assert_nothing_raised do
      PostWithdrawalJob.perform_now(999999, "test_post_123")
    end
  end

  test ".perform_now should do nothing without a freefeed post id" do
    PostWithdrawalJob.perform_now(feed.id, nil)

    assert_not_requested :delete, "#{access_token.host}/v4/posts/test_post_123"
  end

  test ".perform_now should handle authorization errors gracefully" do
    stub_request(:delete, "#{access_token.host}/v4/posts/test_post_123")
      .to_return(status: 401, body: "Unauthorized")

    assert_nothing_raised do
      PostWithdrawalJob.perform_now(feed.id, "test_post_123")
    end
  end
end
