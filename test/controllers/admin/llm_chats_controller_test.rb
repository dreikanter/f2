require "test_helper"

class Admin::LlmChatsControllerTest < ActionDispatch::IntegrationTest
  test "should list retained chats across accounts newest first with pagination" do
    sign_in_as(dev_user)
    older = create(:llm_chat, user: regular_user, created_at: 1.day.ago)
    newer = create(:llm_chat, user: other_user)

    get admin_llm_chats_path, params: { per_page: 1 }

    assert_response :success
    assert_select "h1", "AI API Log"
    assert_select "a[href=?]", development_path, text: "Dev Tools"
    assert_select '[data-key="ai_history.chat"]', count: 1
    assert_select "a[href=?]", admin_llm_chat_path(newer), text: newer.purpose.humanize
    assert_select "a[href=?]", admin_llm_chat_path(older), count: 0
    assert_select '[data-key="ai_history.chat"]' do
      assert_select "p", "#{newer.requested_provider} / #{newer.requested_model} · #{other_user.email_address}"
      assert_select '[data-key="ai_history.status_badge"]', newer.status.humanize
      assert_select "time[datetime=?]", newer.created_at.iso8601
    end

    get admin_llm_chats_path, params: { per_page: 1, page: 2 }

    assert_response :success
    assert_select "a[href=?]", admin_llm_chat_path(older)
    assert_select "a[href=?]", admin_llm_chat_path(newer), count: 0
  end

  test "should read only the selected chat messages and usage without executing requests" do
    sign_in_as(create(:user, :admin, :dev))
    feed = create(:feed, user: regular_user)
    credential = create(:ai_credential, user: regular_user)
    chat = create(:llm_chat, user: regular_user, feed: feed, ai_credential: credential)
    chat.messages.create!(role: "system", content: "Extract items", created_at: 1.minute.ago)
    chat.messages.create!(role: "user", content: "Find today's news", created_at: 30.seconds.ago)
    chat.messages.create!(role: "assistant", content: '<script>alert("hello")</script>')
    usage = create(:ruby_llm_usage, chat: chat, input_tokens: 123, output_tokens: 45)
    unrelated = create(:llm_chat, user: other_user)
    unrelated.messages.create!(role: "user", content: "Private other transcript")
    other_usage = create(:ruby_llm_usage, chat: unrelated)
    original_attributes = chat.attributes
    WebMock.reset!

    assert_no_difference ["LlmChat.count", "LlmMessage.count", "RubyLLM::ActiveRecord::Usage.count"] do
      assert_no_enqueued_jobs do
        get admin_llm_chats_path
        assert_response :success
        get admin_llm_chat_path(chat), params: { user_id: other_user.id, chat_id: unrelated.id }
      end
    end

    assert_response :success
    assert_equal ["System instructions", "User request", "AI response"], css_select('[data-key="ai_history.message"] h3').map(&:text)
    assert_select '[data-key="ai_history.chat_details"] h2', "Chat details"
    assert_select '[data-key="ai_history.messages"] script', count: 0
    assert_select '[data-key="ai_history.content"].whitespace-pre-wrap', count: 3
    assert_includes response.body, "&lt;script&gt;"
    assert_not_includes response.body, "Private other transcript"
    assert_select "[data-llm-usage-id=?]", usage.id
    assert_select "[data-llm-usage-id=?]", other_usage.id, count: 0
    assert_select '[data-key="events.llm_usage.tokens"]', "123 in · 45 out"
    assert_select "a[href=?]", admin_user_path(regular_user)
    assert_select "a[href=?]", admin_feed_path(feed)
    assert_select "a[href=?]", admin_ai_credential_path(credential)
    assert_equal original_attributes, chat.reload.attributes
    assert_empty WebMock::RequestRegistry.instance.requested_signatures.hash
  end

  test "should format JSON responses and show recorded tool call and source fields" do
    sign_in_as(dev_user)
    chat = create(:llm_chat)
    content = { "items" => [{ "title" => "Economic report", "body" => "Definitions differ." }] }
    message = chat.messages.create!(
      role: "assistant",
      content: JSON.generate(content),
      server_tool_calls: [{
        type: "web_search_call",
        name: "web_search",
        id: "search_1",
        input: { query: "economic report" },
        result: { url: "https://example.com/report" },
        raw: { status: "completed", action: { type: "search", query: "economic report" } }
      }],
      citations: [{
        title: "Economic report",
        url: "https://example.com/report",
        cited_text: "Definitions differ."
      }]
    )
    message.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "lookup", arguments: { "query" => "economic report" })

    get admin_llm_chat_path(chat)

    assert_response :success
    assert_select '[data-key="ai_history.messages"] h2', "Conversation"
    assert_select '[data-key="ai_history.message"] h3', "AI response"
    assert_select '[data-key="ai_history.message_header"] time[datetime=?]', message.created_at.iso8601
    assert_select '[data-key="ai_history.message"] > [data-key="ai_history.tool_call"]', count: 2
    assert_select '[data-key="ai_history.tool_call"] h4', text: "Web search call"
    assert_select '[data-key="ai_history.tool_call"] h4', text: "lookup"
    assert_select '[data-key="ai_history.search_query"]', "economic report"
    assert_select '[data-key="ai_history.message"] > div > h4', text: "Sources"
    assert_select '[data-key="ai_history.message"] details', count: 0
    assert_select '[data-key="ai_history.content"].overflow-x-auto.whitespace-pre'
    assert_select '[data-key="ai_history.tool_call"] pre.overflow-x-auto.whitespace-pre', count: 2
    assert_select '[data-key="ai_history.citations"].overflow-x-auto.whitespace-pre'
    assert_select '[data-key="ai_history.usage"] h2', "Token Usage and Cost"
    response_text = css_select('[data-key="ai_history.content"]').sole.text
    assert_equal content, JSON.parse(response_text)
    assert_equal message[:server_tool_calls].sole.fetch("raw"), JSON.parse(css_select('[data-key="ai_history.tool_call"] pre').first.text)
    assert_equal({ "query" => "economic report" }, JSON.parse(css_select('[data-key="ai_history.tool_call"] pre').last.text))
    assert_equal message[:citations], JSON.parse(css_select('[data-key="ai_history.citations"]').sole.text)
  end

  test "should exclude expired chats before they are purged" do
    sign_in_as(dev_user)
    freeze_time do
      expired = create(:llm_chat, created_at: LlmChat::RETENTION.ago)
      retained = create(:llm_chat, created_at: LlmChat::RETENTION.ago + 1.second)
      create(:ruby_llm_usage, chat: expired)

      get admin_llm_chats_path

      assert_response :success
      assert_select "a[href=?]", admin_llm_chat_path(expired), count: 0
      assert_select "a[href=?]", admin_llm_chat_path(retained)

      get admin_llm_chat_path(expired)

      assert_response :not_found
      assert LlmChat.exists?(expired.id)
    end
  end

  test "should render a chat without messages usage feed or credential" do
    travel_to Time.zone.local(2026, 9, 17, 22, 47)
    sign_in_as(dev_user)
    chat = create(:llm_chat, started_at: 13.hours.ago)

    get admin_llm_chat_path(chat)

    assert_response :success
    assert_select "h1", "#{chat.purpose.humanize} #{chat.id.last(5)}"
    assert_select "title", text: /#{chat.purpose.humanize} #{chat.id.last(5)}/
    assert_select 'header [data-key="ai_history.status_badge"]', "Running"
    assert_select "dl dt", text: "Status", count: 0
    assert_select '[data-key="ai_history.started"] time[datetime=?]', chat.started_at.iso8601, text: "17 Sep 2026, 09:47 (13h)"
    assert_select '[data-key="ai_history.messages"]', text: /No messages recorded/
    assert_select '[data-key="ai_history.usage"]', text: /No usage recorded/
  end

  test "should show related records to developers without links to admin pages" do
    sign_in_as(dev_user)
    feed = create(:feed, user: regular_user)
    credential = create(:ai_credential, user: regular_user)
    chat = create(:llm_chat, user: regular_user, feed: feed, ai_credential: credential)

    get admin_llm_chat_path(chat)

    assert_response :success
    assert_select "dd", text: regular_user.email_address
    assert_select "dd", text: feed.name
    assert_select "dd", text: credential.display_name
    assert_select "a[href=?]", admin_user_path(regular_user), count: 0
    assert_select "a[href=?]", admin_feed_path(feed), count: 0
    assert_select "a[href=?]", admin_ai_credential_path(credential), count: 0
  end

  test "should deny the chat owner access without dev permission" do
    sign_in_as(regular_user)
    chat = create(:llm_chat, user: regular_user)

    get admin_llm_chats_path
    assert_redirected_to root_path

    get admin_llm_chat_path(chat)
    assert_redirected_to root_path
  end

  test "should deny another user access to a transcript" do
    sign_in_as(other_user)
    chat = create(:llm_chat, user: regular_user)

    get admin_llm_chat_path(chat)

    assert_redirected_to root_path
  end

  test "should deny admins without dev permission" do
    sign_in_as(admin_user)
    chat = create(:llm_chat)

    get admin_llm_chats_path
    assert_redirected_to root_path

    get admin_llm_chat_path(chat)
    assert_redirected_to root_path
  end

  test "should require authentication" do
    chat = create(:llm_chat)

    get admin_llm_chats_path
    assert_redirected_to new_session_path

    get admin_llm_chat_path(chat)
    assert_redirected_to new_session_path
  end
end
