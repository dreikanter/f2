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
end
