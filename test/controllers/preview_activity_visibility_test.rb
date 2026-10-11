require "test_helper"

class PreviewActivityVisibilityTest < ActionDispatch::IntegrationTest
  test "#show should expose native preview usage to its owner in recent activity and event details" do
    user = create(:user)
    event = create(:event, user: user, type: "feed_preview", level: :info,
                           metadata: { status: "completed", stats: { llm_calls: 1, llm_cost_cents: nil } })
    chat = create(:llm_chat, user: user, purpose: :preview)
    create(:ruby_llm_usage, chat: chat, total_cost: nil, server_tool_use: { "web_search_requests" => 2 })
    event.event_references.create!(reference: chat)
    sign_in_as user

    get events_path
    assert_response :success
    assert_select '[data-event-type="feed_preview"]', text: /AI feed preview completed/
    get event_path(event)
    assert_response :success
    assert_select '[data-key="events.ai_usage"]'
    assert_select '[data-key="events.llm_usage.cost"]', text: "Unknown"
    assert_select '[data-key="events.llm_usage.tokens"]', text: /2 native web searches/

    sign_in_as create(:user)
    get event_path(event)
    assert_response :not_found
  end
end
