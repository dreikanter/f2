require "test_helper"

class PreviewActivityVisibilityTest < ActionDispatch::IntegrationTest
  test "#show should expose native preview usage to its owner in recent activity and event details" do
    user = create(:user)
    event = create(:event, user: user, type: "feed_preview", level: :info,
                           metadata: { status: "completed", stats: { llm_calls: 1, llm_cost_cents: nil } })
    usage = create(:llm_usage, user: user, purpose: :preview, feed: nil, cost_estimate_cents: nil,
                               retrieval: { "mode" => "native", "search_calls" => 1 })
    event.event_references.create!(reference: usage)
    sign_in_as user

    get events_path
    assert_response :success
    assert_select '[data-event-type="feed_preview"]', text: /AI feed preview completed/
    get event_path(event)
    assert_response :success
    assert_select '[data-key="events.ai_usage"]'
    assert_select '[data-key="events.llm_usage.cost"]', text: "Unknown"
    assert_select '[data-key="events.llm_usage.tokens"]', text: /1 native web calls/

    sign_in_as create(:user)
    get event_path(event)
    assert_response :not_found
  end
end
