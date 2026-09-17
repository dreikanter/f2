require "test_helper"

class Admin::LlmChatsControllerTest < ActionDispatch::IntegrationTest
  test "should list retained chats across accounts newest first with pagination" do
    sign_in_as(admin_user)
    older = create(:llm_chat, user: regular_user, created_at: 1.day.ago)
    newer = create(:llm_chat, user: other_user)

    get admin_llm_chats_path, params: { per_page: 1 }

    assert_response :success
    assert_select '[data-key="ai_history.chat"]', count: 1
    assert_select "a[href=?]", admin_llm_chat_path(newer)
    assert_select "a[href=?]", admin_llm_chat_path(older), count: 0

    get admin_llm_chats_path, params: { per_page: 1, page: 2 }

    assert_response :success
    assert_select "a[href=?]", admin_llm_chat_path(older)
    assert_select "a[href=?]", admin_llm_chat_path(newer), count: 0
  end

  test "should read only the selected chat messages and usage without executing requests" do
    sign_in_as(admin_user)
    feed = create(:feed, user: regular_user)
    credential = create(:ai_credential, user: regular_user)
    chat = create(:llm_chat, user: regular_user, feed: feed, ai_credential: credential)
    chat.messages.create!(role: "system", content: "Extract items", created_at: 1.minute.ago)
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
    assert_select '[data-key="ai_history.message"] h3', text: "System"
    assert_equal ["System", "Assistant"], css_select('[data-key="ai_history.message"] h3').map(&:text)
    assert_select '[data-key="ai_history.messages"] script', count: 0
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

  test "should exclude expired chats before they are purged" do
    sign_in_as(admin_user)
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
    sign_in_as(admin_user)
    chat = create(:llm_chat)

    get admin_llm_chat_path(chat)

    assert_response :success
    assert_select '[data-key="ai_history.messages"]', text: /No messages recorded/
    assert_select '[data-key="ai_history.usage"]', text: /No usage recorded/
  end

  test "should deny the chat owner access to admin history" do
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

  test "should deny developers without admin permission" do
    sign_in_as(dev_user)
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
