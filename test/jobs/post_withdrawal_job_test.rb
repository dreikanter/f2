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

    captured = nil
    RateLimit.stub(:acquire!, lambda { |_policy, subject:, cost:|
      captured = [subject, cost]
      raise RateLimit::Throttled.new(retry_after: 2)
    }) do
      assert_enqueued_with(job: PostWithdrawalJob) do
        PostWithdrawalJob.perform_now(feed.id, "test_post_123", post.id)
      end
    end

    assert_equal [access_token.rate_limit_subject, { delete: 1 }], captured
    assert_not_requested :delete, "#{access_token.host}/v4/posts/test_post_123"
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
