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

  test ".perform_now should do nothing when there are no enqueued posts" do
    assert_no_enqueued_jobs(only: PostPublishJob) do
      PostPublishJob.perform_now(feed.id)
    end
  end

  test ".perform_now should return when the feed does not exist" do
    assert_nothing_raised { PostPublishJob.perform_now(-1) }
  end
end
