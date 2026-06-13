require "test_helper"

class PostPublishJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed
    @feed ||= create(:feed, :enabled, user: user, access_token: access_token, target_group: "group")
  end

  def stub_publish_success
    stub_request(:post, "#{access_token.host}/v4/posts")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { posts: { id: "freefeed-#{SecureRandom.hex(8)}" } }.to_json
      )
  end

  test ".perform_now should publish the earliest enqueued post first" do
    older = create(:post, :enqueued, feed: feed, published_at: 2.hours.ago)
    newer = create(:post, :enqueued, feed: feed, published_at: 1.hour.ago)
    stub_publish_success

    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      PostPublishJob.perform_now(feed.id)
    end

    assert_equal "published", older.reload.status
    assert_equal "enqueued", newer.reload.status
  end

  test ".perform_now should publish all enqueued posts through the chain" do
    create(:post, :enqueued, feed: feed, published_at: 3.hours.ago)
    create(:post, :enqueued, feed: feed, published_at: 2.hours.ago)
    create(:post, :enqueued, feed: feed, published_at: 1.hour.ago)
    stub_publish_success

    perform_enqueued_jobs { PostPublishJob.perform_now(feed.id) }

    assert_equal 3, feed.posts.where(status: :published).count
    assert_equal 0, feed.posts.where(status: :enqueued).count
  end

  test ".perform_now should mark a failing post as failed, report it, and continue" do
    post = create(:post, :enqueued, feed: feed)
    stub_request(:post, "#{access_token.host}/v4/posts").to_return(status: 500)

    reported = []
    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      Rails.error.stub(:report, ->(err, **kwargs) { reported << [err, kwargs] }) do
        PostPublishJob.perform_now(feed.id)
      end
    end

    assert_equal "failed", post.reload.status
    assert_equal 1, reported.size
    _error, kwargs = reported.first
    assert_equal post.id, kwargs.dig(:context, :post)["id"]
    assert_equal feed.id, kwargs.dig(:context, :feed)["id"]
  end

  test ".perform_now should disable the token and stop the chain on UnauthorizedError" do
    post = create(:post, :enqueued, feed: feed)
    stub_request(:post, "#{access_token.host}/v4/posts").to_return(status: 401)

    assert_no_enqueued_jobs(only: PostPublishJob) do
      PostPublishJob.perform_now(feed.id)
    end

    assert_equal "inactive", access_token.reload.status
    assert_equal "enqueued", post.reload.status
  end

  test ".perform_now should skip without publishing when a chain is already running" do
    create(:post, :enqueued, feed: feed)
    stub_publish_success

    Feed.stub(:with_advisory_lock!, ->(*, **) { raise WithAdvisoryLock::FailedToAcquireLock.new("post_publish") }) do
      assert_no_enqueued_jobs(only: PostPublishJob) do
        assert_nothing_raised { PostPublishJob.perform_now(feed.id) }
      end
    end

    assert_equal "enqueued", feed.posts.first.reload.status
    assert_not_requested :post, "#{access_token.host}/v4/posts"
  end

  test ".perform_now should stop publishing when the feed was disabled mid-chain" do
    first = create(:post, :enqueued, feed: feed, published_at: 2.hours.ago)
    second = create(:post, :enqueued, feed: feed, published_at: 1.hour.ago)
    stub_publish_success

    # Publish the first post; this enqueues the chained job for the next one.
    PostPublishJob.perform_now(feed.id)
    assert_equal "published", first.reload.status
    assert_enqueued_jobs 1, only: PostPublishJob

    # Disable the feed, then let the already-enqueued chained job run.
    feed.update!(state: :disabled)
    perform_enqueued_jobs(only: PostPublishJob)

    assert_equal "enqueued", second.reload.status
    assert_requested :post, "#{access_token.host}/v4/posts", times: 1
    assert_no_enqueued_jobs(only: PostPublishJob)
  end

  test ".perform_now should count the post, its comments, and its attachments in the reserved cost" do
    create(:post, :enqueued, feed: feed, comments: ["a", "b"], attachment_urls: ["u1", "u2", "u3"])
    subject = access_token.rate_limit_subject

    freeze_time do
      # Leave 5 POST tokens — one short of this post's true cost of 6
      # (1 post + 2 comments + 3 attachments). A run that counted only the post
      # would publish; counting the extras throttles it before any HTTP call.
      drain_freefeed(subject, :post, remaining: 5)

      assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
        PostPublishJob.perform_now(feed.id)
      end
    end

    assert_equal "enqueued", feed.posts.first.reload.status
    assert_not_requested :post, "#{access_token.host}/v4/posts"
  end

  test ".perform_now should fail an oversized post and advance the chain" do
    oversized = create(:post, :enqueued, feed: feed, published_at: 2.hours.ago,
                                         attachment_urls: Array.new(60) { |i| "https://example.com/#{i}.jpg" })
    subject = access_token.rate_limit_subject

    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      PostPublishJob.perform_now(feed.id)
    end

    assert_equal "failed", oversized.reload.status
    assert_not RateLimit::Bucket.exists?(key: "freefeed:#{subject}"),
      "an impossible post must be rejected before reserving any capacity"
  end

  test ".perform_now should reschedule and keep the post enqueued when throttled" do
    post = create(:post, :enqueued, feed: feed)
    subject = access_token.rate_limit_subject

    freeze_time do
      drain_freefeed(subject, :post, remaining: 0)

      assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
        PostPublishJob.perform_now(feed.id)
      end
    end

    assert_equal "enqueued", post.reload.status
    assert_not_requested :post, "#{access_token.host}/v4/posts"
  end

  test ".perform_now should report and keep the post enqueued when throttle retries are exhausted" do
    post = create(:post, :enqueued, feed: feed)
    subject = access_token.rate_limit_subject
    job = PostPublishJob.new(feed.id)
    job.executions = RateLimited::MAX_ATTEMPTS

    reported = []
    freeze_time do
      drain_freefeed(subject, :post, remaining: 0)

      Rails.error.stub(:report, ->(error, **) { reported << error }) do
        assert_no_enqueued_jobs(only: PostPublishJob) { job.perform_now }
      end
    end

    assert_equal 1, reported.size
    assert_instance_of RateLimit::Throttled, reported.first
    assert_equal "enqueued", post.reload.status, "the post must stay enqueued for a later run to pick up"
  end

  test ".perform_now should reschedule without failing when FreeFeed throttles mid-publish" do
    post = create(:post, :enqueued, feed: feed)
    stub_request(:post, "#{access_token.host}/v4/posts")
      .to_return(status: 429, headers: { "Retry-After" => "30" })

    reported = []
    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      Rails.error.stub(:report, ->(*args, **) { reported << args }) do
        PostPublishJob.perform_now(feed.id)
      end
    end

    assert_equal "enqueued", post.reload.status, "the throttled post must stay enqueued for the retry"
    assert_empty reported, "a handled mid-publish throttle must not be reported as a fault"
  end

  test ".perform_now should keep original publication order across a throttle interruption" do
    create(:post, :enqueued, feed: feed, published_at: 3.hours.ago, content: "post-1")
    create(:post, :enqueued, feed: feed, published_at: 2.hours.ago, content: "post-2")
    create(:post, :enqueued, feed: feed, published_at: 1.hour.ago, content: "post-3")

    published_bodies = []
    stub_request(:post, "#{access_token.host}/v4/posts").to_return do |request|
      published_bodies << JSON.parse(request.body).dig("post", "body")
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { posts: { id: "freefeed-#{SecureRandom.hex(8)}" } }.to_json
      }
    end

    subject = access_token.rate_limit_subject

    freeze_time do
      # One POST token: enough for the first post, then the real bucket is dry.
      drain_freefeed(subject, :post, remaining: 1)

      PostPublishJob.perform_now(feed.id) # publishes post-1, bucket -> 0
      PostPublishJob.perform_now(feed.id) # post-2: no tokens, throttles and stays enqueued

      assert_equal ["post-1"], published_bodies
      assert_equal %w[post-2 post-3], feed.posts.enqueued.order(:published_at).pluck(:content),
        "the throttled post and its successor must remain, in order"

      travel(2.seconds)                   # refills one token (post rate is 0.5/s)
      PostPublishJob.perform_now(feed.id) # post-2 resumes — the same post, before post-3
      travel(2.seconds)
      PostPublishJob.perform_now(feed.id) # post-3
    end

    assert_equal %w[post-1 post-2 post-3], published_bodies
    assert_equal 0, feed.posts.enqueued.count
  end

  test ".perform_now should do nothing when there are no enqueued posts" do
    assert_no_enqueued_jobs(only: PostPublishJob) do
      PostPublishJob.perform_now(feed.id)
    end
  end

  test ".perform_now should return when the feed does not exist" do
    assert_nothing_raised { PostPublishJob.perform_now(-1) }
  end
end
