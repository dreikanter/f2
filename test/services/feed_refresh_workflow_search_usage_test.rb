require "test_helper"

class FeedRefreshWorkflowSearchUsageTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  def credential
    @credential ||= create(:search_credential, :active, user: user)
  end

  def started_event
    Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: feed,
      user: user,
      metadata: { status: "started", stats: {} }
    )
  end

  def workflow_with(event)
    FeedRefreshWorkflow.new(feed).tap { |workflow| workflow.instance_variable_set(:@refresh_event, event) }
  end

  def record_searches(event, count)
    Array.new(count) { WebSearchUsage.record!(credential: credential, refresh_event: event) }
  end

  test "completion should transfer search references to the terminal refresh event" do
    started = started_event
    searches = record_searches(started, 2)

    workflow_with(started).send(:complete_refresh_event, [])

    terminal = feed.events.where(type: "feed_refresh").sole
    assert_equal "completed", terminal.metadata.fetch("status")
    assert_equal 2, terminal.metadata.dig("stats", "search_calls")
    assert_equal searches.map(&:id).sort, WebSearchUsage.referenced_by(terminal).pluck(:id).sort
    assert_not Event.exists?(started.id)
  end

  test "failure should transfer search references to the terminal refresh event" do
    started = started_event
    searches = record_searches(started, 3)

    workflow_with(started).send(:fail_refresh_event, StandardError.new("boom"))

    terminal = feed.events.where(type: "feed_refresh").sole
    assert_equal "failed", terminal.metadata.fetch("status")
    assert_equal 3, terminal.metadata.dig("stats", "search_calls")
    assert_equal searches.map(&:id).sort, WebSearchUsage.referenced_by(terminal).pluck(:id).sort
    assert_not Event.exists?(started.id)
  end

  test "interruption should retain search references and add the search count" do
    event = started_event
    searches = record_searches(event, 2)

    workflow_with(event).send(:interrupt_abandoned_event, event)

    event.reload
    assert_equal "interrupted", event.metadata.fetch("status")
    assert_equal 2, event.metadata.dig("stats", "search_calls")
    assert_equal searches.map(&:id).sort, WebSearchUsage.referenced_by(event).pluck(:id).sort
  end
end
