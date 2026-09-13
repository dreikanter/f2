require "test_helper"

class LlmChatTest < ActiveSupport::TestCase
  class Lookup < RubyLLM::Tool
    description "Return a fixture source"
    parameter :query, type: :string

    def execute(query:)
      { title: query, url: "https://example.com/source" }
    end
  end

  test "#messages should reload an ordered SDK exchange with tool results and hosted metadata" do
    tool_response = {
      id: "response_tool", model: "gpt-5-nano", status: "completed",
      output: [{ type: "function_call", call_id: "call_lookup", name: Lookup.tool_name, arguments: '{"query":"News"}' }],
      usage: { input_tokens: 20, output_tokens: 10 }
    }
    response = JSON.parse(file_fixture("llm_transcripts/completed.json").read)
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(body: tool_response)
      .then.to_return_json(body: response)

    record = create(:llm_chat)
    record.context = RubyLLM.context { |config| config.openai_api_key = "test-transcript-key" }
    record.protocol = :responses
    chat = record.to_llm
    record.with_instructions("Find one item.")
    record.with_tools(Lookup)
    record.ask_later("News from today.")
    chat.step until chat.complete?

    # Reading a fresh record must work without credentials or an SDK chat.
    history = LlmChat.find(record.id)
    messages = history.messages.to_a
    assert_equal %w[system user assistant tool assistant], messages.map(&:role)
    assert_equal "Find one item.", messages.first.content
    assert_equal "News from today.", messages.second.content
    call = messages.third.ruby_llm_tool_calls.sole
    assert_equal({ "query" => "News" }, call.arguments)
    assert_equal messages.fourth, call.result
    assert_equal "https://example.com/source", JSON.parse(call.result.content).fetch("url")
    assert_equal '{"items":[]}', messages.last.content
    assert_equal "https://example.com/source", messages.last[:citations].sole.fetch("url")
    assert_equal "web_search_call", messages.last[:server_tool_calls].sole.fetch("type")
    assert_equal response.fetch("output"), messages.last[:raw_content]
    assert_equal "stop", messages.last[:finish_reason]
    assert_equal 2, history.ruby_llm_usages.count
    assert_requested request, times: 2
  end

  test "#finish! should let only the first worker settle a chat" do
    chat = create(:llm_chat)
    stale = LlmChat.find(chat.id)

    freeze_time do
      assert chat.finish!(status: :succeeded)
      assert_not stale.finish!(status: :failed, error_category: "provider_error")
      assert stale.reload.succeeded?
      assert_equal Time.current, stale.finished_at
      assert_nil stale.error_category
    end
  end

  test "#finish! should preserve a failed outcome" do
    chat = create(:llm_chat)

    assert chat.finish!(status: :failed, error_category: "provider_error")
    assert_not chat.finish!(status: :succeeded)
    assert chat.reload.failed?
    assert_equal "provider_error", chat.error_category
  end

  test "#finish! should reject completion at the deadline" do
    chat = create(:llm_chat)

    travel_to chat.deadline_at, with_usec: true do
      assert_not chat.finish!(status: :succeeded)
      assert_not chat.finish!(status: :failed, error_category: "provider_error")
      assert chat.finish!(status: :interrupted, error_category: "deadline_exceeded")
      assert_not chat.finish!(status: :succeeded)
      assert chat.reload.interrupted?
    end
  end

  test "#finish! should reject a nonterminal status" do
    assert_raises(ArgumentError) { create(:llm_chat).finish!(status: :running) }
  end

  test "#update! should protect execution metadata and lifecycle fields" do
    chat = create(:llm_chat)

    assert_raises(ActiveRecord::ReadonlyAttributeError) { chat.update!(requested_model: "other-model") }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { chat.update!(deadline_at: 1.day.from_now) }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { chat.update!(status: :succeeded) }
  end

  test ".unexpired should exclude expired chats from lists and direct lookup" do
    freeze_time do
      expired = create(:llm_chat, created_at: 7.days.ago)
      recent = create(:llm_chat, created_at: 7.days.ago + 1.second)

      assert_equal [recent], LlmChat.unexpired.where(id: [expired.id, recent.id]).to_a
      assert_raises(ActiveRecord::RecordNotFound) { LlmChat.unexpired.find(expired.id) }
      assert_includes LlmChat.expired, expired
    end
  end

  test "#destroy! on a feed and credential should retain the transcript and metadata" do
    owner = create(:user)
    credential = create(:ai_credential, user: owner)
    feed = create(:feed, user: owner)
    chat = create(:llm_chat, user: owner, feed: feed, ai_credential: credential)

    feed.destroy!
    credential.destroy!

    assert_nil chat.reload.feed
    assert_nil chat.ai_credential
    assert_equal owner, chat.user
    assert_equal "openai", chat.requested_provider
    assert_equal "gpt-5-nano", chat.requested_model
    assert_equal "llm", chat.profile_key
  end

  test "#destroy! on an owner should remove their transcripts" do
    chat = create(:llm_chat)
    chat.user.destroy!

    assert_not LlmChat.exists?(chat.id)
  end
end
