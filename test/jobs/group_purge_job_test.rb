require "test_helper"

class GroupPurgeJobTest < ActiveJob::TestCase
  def access_token
    @access_token ||= create(:access_token, :active)
  end

  def feed
    @feed ||= create(:feed, access_token: access_token, target_group: "testgroup")
  end

  test "withdraws all posts with freefeed_post_id from group" do
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    post2 = create(:post, feed: feed, freefeed_post_id: "post2", status: :withdrawn)
    post3 = create(:post, feed: feed, freefeed_post_id: nil, status: :withdrawn)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    GroupPurgeJob.perform_now(access_token.id, "testgroup")

    assert_nil post1.reload.freefeed_post_id
    assert_nil post2.reload.freefeed_post_id
    assert_nil post3.reload.freefeed_post_id
  end

  test "continues on error and logs failure" do
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    post2 = create(:post, feed: feed, freefeed_post_id: "post2", status: :withdrawn)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 500)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    GroupPurgeJob.perform_now(access_token.id, "testgroup")

    assert_equal "post1", post1.reload.freefeed_post_id
    assert_nil post2.reload.freefeed_post_id
  end

  test "exits gracefully if access token not found" do
    assert_nothing_raised do
      GroupPurgeJob.perform_now(999999, "testgroup")
    end
  end

  test "only processes posts for specified group" do
    other_feed = create(:feed, access_token: access_token, target_group: "othergroup")
    post1 = create(:post, feed: feed, freefeed_post_id: "post1", status: :withdrawn)
    post2 = create(:post, feed: other_feed, freefeed_post_id: "post2", status: :withdrawn)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)

    GroupPurgeJob.perform_now(access_token.id, "testgroup")

    assert_nil post1.reload.freefeed_post_id
    assert_equal "post2", post2.reload.freefeed_post_id
  end
end
