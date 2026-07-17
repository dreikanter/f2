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

  test "an attachment 429 should resume without uploading completed attachments again" do
    first = create(:post, :enqueued, feed: feed, published_at: 2.hours.ago,
                                            attachment_urls: ["https://example.com/one", "https://example.com/two"])
    second = create(:post, :enqueued, feed: feed, published_at: 1.hour.ago)
    attachment_attempts = 0
    attached_ids = nil
    post_number = 0
    buffer = Object.new
    buffer.define_singleton_method(:load) { |url| [StringIO.new(url), "text/plain"] }

    stub_request(:post, "#{access_token.host}/v1/attachments").to_return do
      attachment_attempts += 1

      if attachment_attempts == 2
        { status: 429, headers: { "Retry-After" => "30" } }
      else
        {
          status: 201,
          headers: { "Content-Type" => "application/json" },
          body: { attachments: { id: "ff-attachment-#{attachment_attempts}" } }.to_json
        }
      end
    end

    stub_request(:post, "#{access_token.host}/v4/posts").to_return do |request|
      post_number += 1
      attached_ids ||= JSON.parse(request.body).dig("post", "attachments")
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { posts: { id: "ff-post-#{post_number}" } }.to_json
      }
    end

    allow_rate_limit do
      FileBuffer.stub(:new, buffer) do
        assert_no_enqueued_jobs(only: PostPublishJob) do
          PostPublishJob.perform_now(feed.id)
        end

        publication = first.reload.post_publication
        assert_predicate first, :enqueued?
        assert_equal 1, publication.attachments_processed_count
        assert_equal ["ff-attachment-1"], publication.uploaded_attachment_ids
        assert_predicate second.reload, :enqueued?, "newer posts must wait behind the throttled attachment"

        perform_enqueued_jobs(only: PostPublishJob) do
          PublicationSchedulerJob.perform_now
        end
      end
    end

    assert_nil first.reload.post_publication
    assert_predicate first, :published?
    assert_predicate second.reload, :published?
    assert_equal 3, attachment_attempts, "the completed attachment must not be uploaded again"
    assert_equal ["ff-attachment-1", "ff-attachment-3"], attached_ids
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

      publication = first.reload.post_publication
      assert_predicate first, :published?
      assert_equal 1, publication.comments_published_count
      assert_predicate second.reload, :enqueued?, "newer posts must wait behind the throttled comment"

      perform_enqueued_jobs(only: PostPublishJob) do
        PublicationSchedulerJob.perform_now
      end
    end

    assert_nil first.reload.post_publication
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
    assert_nil first.post_publication
    assert_predicate second.reload, :published?, "the comment failure must not block newer posts"

    event = Event.where(type: "feed_post_comments_failed", subject: feed).last
    assert_not_nil event
    assert_predicate event, :error?
    assert_equal first.id, event.metadata["post_id"]
    assert_equal first.freefeed_post_id, event.metadata["freefeed_post_id"]
    assert_equal 1, reported.size
  end

  test "withdrawing a post with pending comments prevents it from being resumed" do
    first = create(:post, :enqueued, feed: feed, published_at: 2.hours.ago,
                                            content: "first post", comments: ["comment"])
    second = create(:post, :enqueued, feed: feed, published_at: 1.hour.ago, content: "second post")
    published_bodies = []
    post_number = 0

    stub_request(:post, "#{access_token.host}/v4/posts").to_return do |request|
      post_number += 1
      published_bodies << JSON.parse(request.body).dig("post", "body")
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { posts: { id: "ff-post-#{post_number}" } }.to_json
      }
    end
    stub_request(:post, "#{access_token.host}/v4/comments")
      .to_return(status: 429, headers: { "Retry-After" => "30" })
    stub_request(:delete, "#{access_token.host}/v4/posts/ff-post-1").to_return(status: 200)

    allow_rate_limit do
      assert_no_enqueued_jobs(only: PostPublishJob) do
        PostPublishJob.perform_now(feed.id)
      end

      first.reload
      assert_predicate first, :published?
      assert_not_nil first.post_publication

      first.withdrawn!
      PostWithdrawalJob.perform_now(feed.id, first.freefeed_post_id, first.id)

      perform_enqueued_jobs(only: PostPublishJob) do
        PublicationSchedulerJob.perform_now
      end
    end

    first.reload
    assert_predicate first, :withdrawn?
    assert_nil first.freefeed_post_id
    assert_nil first.post_publication
    assert_predicate second.reload, :published?
    assert_equal ["first post", "second post"], published_bodies
  end

  private

  def allow_rate_limit(&block)
    result = RateLimit::Result.new(allowed: true, retry_after: nil)
    RateLimit.stub(:acquire, result, &block)
  end
end