require "test_helper"

class FeedPurgeTest < ActionDispatch::IntegrationTest
  def queue_adapter_for_test
    ActiveJob::QueueAdapters::SolidQueueAdapter.new
  end

  def feed
    @feed ||= create(:feed, :enabled)
  end

  def purge_jobs
    SolidQueue::Job.where(class_name: WithdrawAllPostsJob.name)
  end

  def claim_purge
    worker = create(:solid_queue_process)

    SolidQueue::ReadyExecution.where(job_id: purge_jobs.select(:id))
      .claim([WithdrawAllPostsJob.queue_name], 1, worker.id).sole
  end

  def start_purge
    sign_in_as(feed.user)
    post feed_purge_path(feed)
    assert_redirected_to feed_path(feed)
  end

  test "#create should disable immediately and prevent duplicate queued and running purges" do
    start_purge

    assert feed.reload.disabled?
    assert feed.purging?
    assert_equal 1, feed.events.where(type: "feed_disabled").count
    assert_equal [feed.id, feed.user_id], purge_jobs.sole.arguments.fetch("arguments")

    assert_no_difference -> { purge_jobs.count } do
      post feed_purge_path(feed)
    end

    assert_equal "Feed purge is already in progress.", flash[:alert]

    claim_purge
    assert feed.purging?

    assert_no_difference -> { purge_jobs.count } do
      post feed_purge_path(feed)
    end
  end

  test "#show should warn in confirmation and show progress across reloads until completion" do
    sign_in_as(feed.user)
    get feed_path(feed)
    assert_select "#purge-modal-#{feed.id}", text: /disables the feed when the purge starts/

    start_purge

    2.times do
      get feed_path(feed)
      assert_select '[data-key="feed.purging"][role="alert"]', text: /Feed purge is in progress/
      assert_select "[data-key='feed.#{feed.id}.purge']", count: 0
      assert_select '[data-key="feed.header"][data-controller="polling"][data-polling-max-polls-value="0"]'
    end

    event = feed.events.user_relevant.recent.first
    get feed_path(feed, format: :turbo_stream), params: { after_id: event.id, refresh_after: "none", purging: "1" }
    assert_empty response.body

    # Activity advances the polling cursor without making every later poll redraw the page.
    activity = create(:event, type: "group_purge_started", subject: feed, user: feed.user)
    get feed_path(feed, format: :turbo_stream), params: { after_id: event.id, refresh_after: "none", purging: "1" }
    assert_select '[data-key="feed.header"][data-last-event-id=?]', activity.id
    assert_select '[data-key="feed.purging"]'

    execution = claim_purge
    assert feed.purging?
    execution.perform
    assert_not feed.purging?
    assert feed.reload.disabled?

    # Completion updates the existing event, so the event id alone cannot stop polling.
    event = feed.events.user_relevant.recent.first
    get feed_path(feed, format: :turbo_stream), params: { after_id: event.id, refresh_after: "none", purging: "1" }
    assert_select "turbo-stream[target='header_feed_#{feed.id}']"
    assert_select '[data-key="feed.purging"]', count: 0
    assert_select "[data-key='feed.#{feed.id}.purge']", text: "Purge feed…"
    assert_select '[data-controller="polling"]', count: 0
  end

  test "#purging? should track only this feed's purge and ignore failed or discarded jobs" do
    start_purge
    other = create(:feed, :enabled, user: feed.user)
    assert_not other.purging?
    FeedRefreshJob.perform_later(other.id)
    assert_not other.purging?

    failure = ->(*) { raise "purge failed" }
    WithdrawAllPosts.stub(:new, failure) do
      assert_raises(RuntimeError) { claim_purge.perform }
    end

    assert_not feed.purging?
    assert feed.reload.disabled?

    assert_difference -> { purge_jobs.count }, 1 do
      post feed_purge_path(feed)
    end

    assert feed.purging?
    purge_jobs.where.missing(:failed_execution).sole.destroy!
    assert_not feed.purging?
  end

  test "#create should roll back disabling and its event when enqueue fails" do
    sign_in_as(feed.user)
    enqueue = ->(*) { raise ActiveJob::EnqueueError, "queue unavailable" }

    WithdrawAllPostsJob.stub(:perform_later, enqueue) do
      assert_raises(ActiveJob::EnqueueError) { post feed_purge_path(feed) }
    end

    assert feed.reload.enabled?
    assert_empty feed.events.where(type: "feed_disabled")
    assert_not feed.purging?
  end

  test "#perform should clear progress when the token becomes inactive before execution" do
    start_purge
    feed.access_token.update!(state: :inactive)
    claim_purge.perform

    assert_not feed.purging?
    assert feed.reload.disabled?
  end
end
