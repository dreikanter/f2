require "test_helper"

class PostWithdrawalJobTest < ActiveJob::TestCase
  def access_token
    @access_token ||= create(:access_token, :active)
  end

  def feed
    @feed ||= create(:feed, access_token: access_token)
  end

  def post
    @post ||= create(:post, feed: feed, freefeed_post_id: "test_post_123", status: :withdrawn)
  end

  test ".perform_now should delete post from FreeFeed" do
    stub_request(:delete, "#{access_token.host}/v4/posts/test_post_123")
      .to_return(status: 200)

    PostWithdrawalJob.perform_now(post.id)

    assert_requested :delete, "#{access_token.host}/v4/posts/test_post_123"
  end

  test ".perform_now should handle FreeFeed API errors gracefully" do
    stub_request(:delete, "#{access_token.host}/v4/posts/test_post_123")
      .to_return(status: 500, body: "Internal Server Error")

    assert_nothing_raised do
      PostWithdrawalJob.perform_now(post.id)
    end
  end

  test ".perform_now should handle missing post gracefully" do
    assert_nothing_raised do
      PostWithdrawalJob.perform_now(999999)
    end
  end

  test ".perform_now should handle authorization errors gracefully" do
    stub_request(:delete, "#{access_token.host}/v4/posts/test_post_123")
      .to_return(status: 401, body: "Unauthorized")

    assert_nothing_raised do
      PostWithdrawalJob.perform_now(post.id)
    end
  end
end
