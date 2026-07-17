require "test_helper"

class PostCommentDeliveryTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed
    @feed ||= create(:feed, :enabled, user: user, access_token: access_token, target_group: "group")
  end

  test "a comment 429 should pause the queue and resume without duplicates" do
    first = create(:post, :enqueued, feed: feed, published_at: 2.hours.ago,
                                            comments: ["first comment", "second comment"])
    second = create(:post, :enqueued, feed: feed, published_at: 1.hour.ago)
    post_number = 0
    comment_attempts = Hash.new(0)

    stub_request(:post, "#{access_token.host}/v4/posts").to_return do
      post_number += 1
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { posts: { id: "ff-post-#{post_number}" } }.to_json
      }
    end

    stub_request(:post, "#{access_token.host}/v4/comments").to_return do |request|
      body = JSON.parse(request.body).dig("comment", "body")
      comment_attempts[body] += 1

      if body == "second comment" && comment_attempts[body] == 1
        { status: 429, headers: { "Retry-After" => "30" } }
      else
        {
          status: 201,
          headers: { "Content-Type" => "application/json" },
          body: { comments: { id: SecureRandom.uuid } }.to_json
        }
      end
    end

    allow_rate_limit do
      assert_no_enqueued_jobs(only: PostPublishJob) do
        PostPublishJob.perform_now(feed.id)
      end

      first.reload
      assert_predicate first, :published?
      assert_equal 1, first.next_comment_index
      assert_predicate second.reload, :enqueued?, "newer posts must wait behind the throttled comment"

      assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
        PublicationSchedulerJob.perform_now
      end
      perform_enqueued_jobs(only: PostPublishJob)
    end

    assert_nil first.reload.next_comment_index
    assert_predicate second.reload, :published?
    assert_equal 1, comment_attempts["first comment"], "a completed comment must not be duplicated"
    assert_equal 2, comment_attempts["second comment"], "the interrupted comment should be retried"
  end

  test "an ordinary comment error should keep the post published, notify the user, and continue" do
    first = create(:post, :enqueued, feed: feed, published_at: 2.hours.ago, comments: ["comment"])
    second = create(:post, :enqueued, feed: feed, published_at: 1.hour.ago)
    post_number = 0

    stub_request(:post, "#{access_token.host}/v4/posts").to_return do
      post_number += 1
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { posts: { id: "ff-post-#{post_number}" } }.to_json
      }
    end
    stub_request(:post, "#{access_token.host}/v4/comments").to_return(status: 500)

    reported = []
    allow_rate_limit do
      Rails.error.stub(:report, ->(error, **) { reported << error }) do
        perform_enqueued_jobs(only: PostPublishJob) { PostPublishJob.perform_now(feed.id) }
      end
    end

    first.reload
    assert_predicate first, :published?
    assert_nil first.next_comment_index
    assert_predicate second.reload, :published?, "the comment failure must not block newer posts"

    event = Event.where(type: "feed_post_comments_failed", subject: feed).last
    assert_not_nil event
    assert_predicate event, :error?
    assert_equal first.id, event.metadata["post_id"]
    assert_equal first.freefeed_post_id, event.metadata["freefeed_post_id"]
    assert_equal 1, reported.size
  end

  private

  def allow_rate_limit(&block)
    result = RateLimit::Result.new(allowed: true, retry_after: nil)
    RateLimit.stub(:acquire, result, &block)
  end
end
