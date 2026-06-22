require "test_helper"

class WithdrawAllPostsTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed
    @feed ||= create(:feed, user: user, access_token: access_token, target_group: "testgroup")
  end

  def service
    @service ||= WithdrawAllPosts.new(feed, user: user)
  end

  test "#call should delete FreeFeed posts and mark them withdrawn" do
    post1 = create(:post, :published, feed: feed, freefeed_post_id: "post1")
    post2 = create(:post, :published, feed: feed, freefeed_post_id: "post2")
    post3 = create(:post, feed: feed, freefeed_post_id: nil)
    post4 = create(:post, :published, feed: feed, freefeed_post_id: nil)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    service.call

    assert_nil post1.reload.freefeed_post_id
    assert_predicate post1.reload, :withdrawn?
    assert_nil post2.reload.freefeed_post_id
    assert_predicate post2.reload, :withdrawn?
    assert_not_predicate post3.reload, :withdrawn?, "non-published posts without a FreeFeed ID are not touched"
    assert_not_predicate post4.reload, :withdrawn?, "published posts without a FreeFeed ID are not touched"
  end

  test "#call should recompute published metrics for affected dates" do
    post1 = create(:post, :published, feed: feed, freefeed_post_id: "post1")
    metric = create(:feed_metric, :with_published_posts, feed: feed, date: post1.reposted_at.to_date)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)

    service.call

    assert_equal 0, metric.reload.published_posts_count
  end

  test "#call should reserve one delete token per post" do
    create(:post, :published, feed: feed, freefeed_post_id: "post1")
    create(:post, :published, feed: feed, freefeed_post_id: "post2")
    subject = access_token.rate_limit_subject

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    freeze_time do
      service.call

      capacity = RateLimit.capacity(:freefeed, :delete)
      assert_equal capacity - 2, freefeed_tokens_left(subject, :delete),
        "two withdrawals must spend exactly two delete tokens"
    end
  end

  test "#call should sleep and continue instead of raising when throttled" do
    post1 = create(:post, :published, feed: feed, freefeed_post_id: "post1")

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)

    acquire_call = 0
    acquire_stub = ->(*args, **kwargs) {
      acquire_call += 1
      acquire_call == 1 ? RateLimit::Result.new(allowed: false, retry_after: 5.0)
                        : RateLimit::Result.new(allowed: true, retry_after: 0.0)
    }

    slept = []

    RateLimit.stub(:acquire, acquire_stub) do
      service.stub(:sleep, ->(n) { slept << n }) do
        service.call
      end
    end

    assert_equal [5.0], slept
    assert_nil post1.reload.freefeed_post_id
  end

  test "#call should sleep and retry when FreeFeed throttles a DELETE" do
    post1 = create(:post, :published, feed: feed, freefeed_post_id: "post1")
    stub_request(:delete, "#{access_token.host}/v4/posts/post1")
      .to_return(status: 429, headers: { "Retry-After" => "30" })
      .then.to_return(status: 200)

    slept = []
    reported = []

    service.stub(:sleep, ->(n) { slept << n; travel(n.ceil.seconds + 1) }) do
      Rails.error.stub(:report, ->(*args, **) { reported << args }) do
        service.call
      end
    end

    assert_empty reported, "throttling must not be reported as a fault"
    assert_not_empty slept
    assert_nil post1.reload.freefeed_post_id
  end

  test "#call should sync the record when the FreeFeed post is already gone" do
    post1 = create(:post, :published, feed: feed, freefeed_post_id: "post1")
    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 404)

    service.call

    assert_nil post1.reload.freefeed_post_id
    assert_predicate post1.reload, :withdrawn?
  end

  test "#call should skip failed deletes and continue to the next post" do
    post1 = create(:post, :published, feed: feed, freefeed_post_id: "post1")
    post2 = create(:post, :published, feed: feed, freefeed_post_id: "post2")

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 500)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    service.call

    assert_equal "post1", post1.reload.freefeed_post_id
    assert_predicate post1.reload, :published?, "status unchanged when DELETE fails"
    assert_nil post2.reload.freefeed_post_id
    assert_predicate post2.reload, :withdrawn?
  end

  test "#call should create a group_purge_started event for the feed" do
    assert_difference("Event.count", 1) do
      service.call
    end

    event = Event.last
    assert_equal "group_purge_started", event.type
    assert_equal user, event.user
    assert_equal feed, event.subject
    assert_equal "info", event.level
    assert_equal "testgroup", event.metadata["target_group"]
  end

  test "#call should update the event with completion stats" do
    date1 = Date.new(2024, 1, 10)
    date2 = Date.new(2024, 1, 20)
    create(:post, :published, feed: feed, freefeed_post_id: "post1", reposted_at: date1.to_time)
    create(:post, :published, feed: feed, freefeed_post_id: "post2", reposted_at: date2.to_time)

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)
    stub_request(:delete, "#{access_token.host}/v4/posts/post2").to_return(status: 200)

    service.call

    event = Event.last
    assert_equal 2, event.metadata["deleted_count"]
    assert_not_nil event.metadata["duration_seconds"]
    assert_equal "2024-01-10", event.metadata["dates_from"]
    assert_equal "2024-01-20", event.metadata["dates_to"]
  end

  test "#call should only process posts belonging to the given feed" do
    other_feed = create(:feed, user: user, access_token: access_token, target_group: "othergroup")
    post1 = create(:post, :published, feed: feed, freefeed_post_id: "post1")
    post2 = create(:post, :published, feed: other_feed, freefeed_post_id: "post2")

    stub_request(:delete, "#{access_token.host}/v4/posts/post1").to_return(status: 200)

    service.call

    assert_nil post1.reload.freefeed_post_id
    assert_equal "post2", post2.reload.freefeed_post_id
  end
end
