require "test_helper"

class FeedRefreshWorkflowTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, loader: "http", processor: "rss", normalizer: "rss")
  end

  test "initializes workflow with feed and stats" do
    workflow = FeedRefreshWorkflow.new(feed)

    assert_equal feed, workflow.feed
    assert_equal({}, workflow.stats)
  end

  test "workflow has correct step sequence defined" do
    expected_steps = [
      :initialize_workflow,
      :load_feed_contents,
      :process_feed_contents,
      :filter_new_entries,
      :persist_entries,
      :normalize_entries,
      :persist_posts,
      :finalize_workflow
    ]

    assert_equal expected_steps, FeedRefreshWorkflow.workflow_steps
  end

  test "provides access to timing information" do
    workflow = FeedRefreshWorkflow.new(feed)

    assert_equal({}, workflow.step_durations)
    assert_equal 0.0, workflow.total_duration
    assert_nil workflow.current_step
  end

  test "records workflow statistics during execution" do
    workflow = FeedRefreshWorkflow.new(feed)

    # Test that stats are properly initialized and tracked
    assert_equal({}, workflow.stats)
    assert_equal 0.0, workflow.total_duration

    # Create a simple workflow without external dependencies to test stats recording
    def workflow.load_feed_contents(*)
      record_stats(content_size: 100)
      "simple content"
    end

    def workflow.process_feed_contents(raw_data)
      record_stats(total_entries: 1)
      []
    end

    def workflow.filter_new_entries(entries)
      entries
    end

    def workflow.persist_entries(entries)
      record_stats(new_entries: 0)
      []
    end

    def workflow.normalize_entries(entries)
      entries
    end

    def workflow.persist_posts(posts)
      record_stats(new_posts: 0)
      posts
    end

    workflow.execute

    # Verify stats were recorded at each step
    assert workflow.stats[:started_at]
    assert_equal 100, workflow.stats[:content_size]
    assert_equal 1, workflow.stats[:total_entries]
    assert_equal 0, workflow.stats[:new_entries]
    assert_equal 0, workflow.stats[:new_posts]
    assert workflow.stats[:completed_at]
    assert workflow.stats[:total_duration] >= 0

    # Verify stats event was created
    events = Event.where(subject: feed, type: "feed_refresh_stats")
    assert_equal 1, events.count
  end
end
