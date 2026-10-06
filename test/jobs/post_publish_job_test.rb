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

  test ".perform_now should record the daily published metric" do
    create(:post, :enqueued, feed: feed, published_at: 1.hour.ago)
    stub_publish_success

    perform_enqueued_jobs { PostPublishJob.perform_now(feed.id) }

    metric = FeedMetric.find_by(feed: feed, date: Date.current)
    assert_equal 1, metric.published_posts_count
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

  test ".perform_now should fail an interrupted post without republishing or reserving capacity" do
    post = create(:post, :enqueued, feed: feed)
    post.create_post_publication!(post_create_started_at: 5.minutes.ago)
    subject = access_token.rate_limit_subject
    stub_publish_success

    reported = []
    freeze_time do
      Rails.error.stub(:report, ->(error, **) { reported << error }) do
        PostPublishJob.perform_now(feed.id)
      end

      assert_equal "failed", post.reload.status
      assert_nil post.post_publication
      assert_not_requested(:post, "#{access_token.host}/v4/posts")
      assert_equal 1, reported.size
      assert_instance_of FreefeedPublisher::InterruptedPublicationError, reported.first
      assert_equal RateLimit.capacity(:freefeed, :post), freefeed_tokens_left(subject, :post),
        "an interrupted post must be failed before reserving any capacity"
    end

    event = Event.where(type: "feed_post_publication_interrupted", subject: feed).last
    assert_not_nil event
    assert_predicate event, :error?
    assert_equal post.id, event.metadata["post_id"]
  end

  test ".perform_now should fail a post with an unfetchable attachment without reporting it" do
    post = create(:post, :enqueued, feed: feed, attachment_urls: ["https://example.com/missing.png"])
    stub_request(:get, "https://example.com/missing.png").to_return(status: 404, body: "Not Found")

    reported = []
    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      Rails.error.stub(:report, ->(*args, **) { reported << args }) do
        PostPublishJob.perform_now(feed.id)
      end
    end

    assert_equal "failed", post.reload.status
    assert_empty reported, "an expected attachment 404 must not be reported as a fault"
  end

  test ".perform_now should publish a post whose comment exceeds the length limit without wedging" do
    # A post that slipped into the queue (via bulk insert) with an over-long
    # comment must not wedge the chain: marking it published, and the fallback
    # to failed, both re-run the comment-length validation.
    post = build(:post, :enqueued, feed: feed, comments: ["a" * (Post::MAX_COMMENT_LENGTH + 1)])
    post.save!(validate: false)
    stub_publish_success
    stub_request(:post, "#{access_token.host}/v4/comments")
      .to_return(status: 201, headers: { "Content-Type" => "application/json" }, body: { comments: { id: "c1" } }.to_json)

    assert_nothing_raised { PostPublishJob.perform_now(feed.id) }
    assert_equal "published", post.reload.status
  end

  test ".perform_now should disable the token and stop the chain on UnauthorizedError" do
    post = create(:post, :enqueued, feed: feed)
    stub_request(:post, "#{access_token.host}/v4/posts").to_return(status: 401)

    assert_no_enqueued_jobs(only: PostPublishJob) do
      PostPublishJob.perform_now(feed.id)
    end

    assert_equal "inactive", access_token.reload.state
    assert_equal "enqueued", post.reload.status
  end

  test ".perform_now should disable only this feed and record an event when the group is unavailable" do
    post = create(:post, :enqueued, feed: feed)
    stub_request(:post, "#{access_token.host}/v4/posts")
      .to_return(status: 403, body: { err: "You can not post to some of destinations: group" }.to_json)

    assert_no_enqueued_jobs(only: PostPublishJob) do
      PostPublishJob.perform_now(feed.id)
    end

    assert_equal "disabled", feed.reload.state
    assert_equal "active", access_token.reload.state
    assert_equal "enqueued", post.reload.status

    event = Event.where(type: "feed_target_group_unavailable", subject: feed).last
    assert_not_nil event
    assert_equal "warning", event.level
    assert_equal "posting_denied", event.metadata["reason"]
    assert_equal "group", event.metadata["target_group"]
    # Raw API text is kept in metadata for diagnostics.
    assert_equal "You can not post to some of destinations: group", event.metadata["details"]
    assert_equal "", event.message
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

  test ".perform_now should wait for all three requests of a small publication" do
    image = "https://example.com/image.jpg"
    post = create(:post, :enqueued, feed: feed, attachment_urls: [image], comments: ["Caption"])
    stub_request(:get, image)
      .to_return(status: 200, body: "image_data", headers: { "Content-Type" => "image/jpeg" })
    stub_request(:post, "#{access_token.host}/v1/attachments")
      .to_return(status: 201, body: { attachments: { id: "attachment" } }.to_json)
    stub_publish_success
    stub_request(:post, "#{access_token.host}/v4/comments")
      .to_return(status: 201, body: { comments: { id: "comment" } }.to_json)

    freeze_time do
      drain_freefeed(access_token.rate_limit_subject, :post, remaining: 2)

      assert_enqueued_with(job: PostPublishJob, args: [feed.id]) { PostPublishJob.perform_now(feed.id) }

      assert_predicate post.reload, :enqueued?
      assert_not_requested :get, image
      assert_not_requested :post, "#{access_token.host}/v1/attachments"
      assert_not_requested :post, "#{access_token.host}/v4/posts"
      assert_not_requested :post, "#{access_token.host}/v4/comments"

      travel(2.seconds)
      PostPublishJob.perform_now(feed.id)

      assert_predicate post.reload, :published?
      assert_nil post.post_publication
      assert_equal 0, freefeed_tokens_left(access_token.rate_limit_subject, :post)
    end

    assert_requested :post, "#{access_token.host}/v1/attachments", times: 1
    assert_requested :post, "#{access_token.host}/v4/posts", times: 1
    assert_requested :post, "#{access_token.host}/v4/comments", times: 1
  end

  test ".perform_now should publish incrementally when four requests remain" do
    post = create(:post, :enqueued, feed: feed, comments: %w[first second third])
    delivered_comments = []
    stub_publish_success
    stub_request(:post, "#{access_token.host}/v4/comments").to_return do |request|
      delivered_comments << JSON.parse(request.body).dig("comment", "body")
      { status: 201, body: { comments: { id: SecureRandom.uuid } }.to_json }
    end

    freeze_time do
      drain_freefeed(access_token.rate_limit_subject, :post, remaining: 3)

      assert_no_enqueued_jobs(only: PostPublishJob) { PostPublishJob.perform_now(feed.id) }

      assert_predicate post.reload, :published?
      assert_equal 2, post.post_publication.comments_published_count
      assert_equal %w[first second], delivered_comments

      travel(2.seconds)
      PostPublishJob.perform_now(feed.id)
    end

    assert_nil post.reload.post_publication
    assert_equal %w[first second third], delivered_comments
    assert_requested :post, "#{access_token.host}/v4/posts", times: 1
  end

  test ".perform_now should reserve only the three remaining comments on resume" do
    comments = Array.new(20) { |index| "Paragraph #{index + 1}." }
    images = Array.new(20) { |index| "https://example.com/#{index}.jpg" }
    post = create(:post, :published, feed: feed, comments: comments, attachment_urls: images)
    post.create_post_publication!(comments_published_count: 17, attachments_processed_count: 20)
    delivered_comments = []
    stub_request(:post, "#{access_token.host}/v4/comments").to_return do |request|
      delivered_comments << JSON.parse(request.body).dig("comment", "body")
      { status: 201, body: { comments: { id: SecureRandom.uuid } }.to_json }
    end

    freeze_time do
      drain_freefeed(access_token.rate_limit_subject, :post, remaining: 2)
      PostPublishJob.perform_now(feed.id)

      assert_equal 17, post.reload.post_publication.comments_published_count
      assert_empty delivered_comments

      travel(2.seconds)
      PostPublishJob.perform_now(feed.id)

      assert_nil post.reload.post_publication
      assert_equal comments.last(3), delivered_comments
      assert_equal 0, freefeed_tokens_left(access_token.rate_limit_subject, :post)
    end

    assert_not_requested :post, "#{access_token.host}/v1/attachments"
    assert_not_requested :post, "#{access_token.host}/v4/posts"
  end

  test ".perform_now should reserve each attachment, post, and comment as it is sent" do
    images = %w[https://example.com/one.jpg https://example.com/two.jpg https://example.com/three.jpg]
    post = create(:post, :enqueued, feed: feed, comments: ["a", "b"], attachment_urls: images)
    delivered_comments = []
    stub_request(:get, %r{https://example.com/(one|two|three)\.jpg})
      .to_return(status: 200, body: "image_data", headers: { "Content-Type" => "image/jpeg" })
    stub_request(:post, "#{access_token.host}/v1/attachments")
      .to_return(status: 201, body: { attachments: { id: "attachment" } }.to_json)
    stub_publish_success
    stub_request(:post, "#{access_token.host}/v4/comments").to_return do |request|
      delivered_comments << JSON.parse(request.body).dig("comment", "body")
      { status: 201, body: { comments: { id: SecureRandom.uuid } }.to_json }
    end

    freeze_time do
      drain_freefeed(access_token.rate_limit_subject, :post, remaining: 5)

      assert_no_enqueued_jobs(only: PostPublishJob) { PostPublishJob.perform_now(feed.id) }

      assert_predicate post.reload, :published?
      assert_equal 3, post.post_publication.attachments_processed_count
      assert_equal 1, post.post_publication.comments_published_count
      assert_equal ["a"], delivered_comments

      travel(2.seconds)
      PostPublishJob.perform_now(feed.id)
    end

    assert_nil post.reload.post_publication
    assert_equal ["a", "b"], delivered_comments
    assert_requested :post, "#{access_token.host}/v1/attachments", times: 3
    assert_requested :post, "#{access_token.host}/v4/posts", times: 1
  end

  test ".perform_now should resume a large comment set over multiple refills before newer posts" do
    comments = Array.new(45) { |index| "Paragraph #{index + 1}." }
    post = create(:post, :enqueued, feed: feed, published_at: 2.hours.ago, comments: comments)
    newer = create(:post, :enqueued, feed: feed, published_at: 1.hour.ago)
    delivered_comments = []
    stub_publish_success
    stub_request(:post, "#{access_token.host}/v4/comments").to_return do |request|
      delivered_comments << JSON.parse(request.body).dig("comment", "body")
      { status: 201, body: { comments: { id: SecureRandom.uuid } }.to_json }
    end

    freeze_time do
      assert_no_enqueued_jobs(only: PostPublishJob) { PostPublishJob.perform_now(feed.id) }

      assert_predicate post.reload, :published?
      assert_equal 19, post.post_publication.comments_published_count
      assert_equal comments.first(19), delivered_comments
      assert_predicate newer.reload, :enqueued?

      travel(40.seconds)
      perform_enqueued_jobs(only: PostPublishJob) { PublicationSchedulerJob.perform_now }

      assert_equal 39, post.reload.post_publication.comments_published_count
      assert_equal comments.first(39), delivered_comments
      assert_predicate newer.reload, :enqueued?

      travel(14.seconds)
      perform_enqueued_jobs(only: PostPublishJob) { PublicationSchedulerJob.perform_now }

      assert_equal 0, freefeed_tokens_left(access_token.rate_limit_subject, :post)
    end

    assert_nil post.reload.post_publication
    assert_equal comments, delivered_comments
    assert_predicate newer.reload, :published?
    assert_requested :post, "#{access_token.host}/v4/posts", times: 2
    assert_equal 2, FeedMetric.where(feed: feed).sum(:published_posts_count)
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

  # Best-effort publishing: once the post is created its id is persisted, so a
  # 429 on a later comment leaves the post published with an incomplete comment
  # set rather than re-creating it. Documents the accepted behaviour (see
  # FreefeedPublisher#publish) so it stays predictable and safe.
  test ".perform_now should leave the post published and not duplicated when a comment is throttled" do
    post = create(:post, :enqueued, feed: feed, content: "body", comments: ["c1", "c2"])

    stub_request(:post, "#{access_token.host}/v4/posts")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { posts: { id: "ff-post-1" } }.to_json)
    # FreeFeed throttles the first comment, after the post itself was created.
    stub_request(:post, "#{access_token.host}/v4/comments")
      .to_return(status: 429, headers: { "Retry-After" => "30" })

    reported = []
    increments = []
    Metrics.stub(:increment, ->(name, **tags) { increments << [name, tags] }) do
      Rails.error.stub(:report, ->(*args, **) { reported << args }) do
        perform_enqueued_jobs { PostPublishJob.perform_now(feed.id) }
      end
    end

    post.reload
    assert_equal "published", post.status, "the created post is recorded as published"
    assert_equal "ff-post-1", post.freefeed_post_id
    # The post is created exactly once and never re-created on the retry chain.
    assert_requested :post, "#{access_token.host}/v4/posts", times: 1
    # Comment creation pauses at the throttled comment until the scheduler resumes it.
    assert_requested :post, "#{access_token.host}/v4/comments", times: 1
    assert_empty reported, "a handled mid-comment throttle must not be reported as a fault"

    published = increments.count { |name, tags| name == "posts_published_total" && tags[:status] == "published" }
    assert_equal 1, published, "a created post is counted once even when a comment throttles"
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
      PostPublishJob.perform_now(feed.id) # post-2 resumes: the same post, before post-3
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
