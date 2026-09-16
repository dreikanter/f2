require "test_helper"

class LlmChatTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
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

  test "#create! should schedule interruption at the capped deadline" do
    freeze_time do
      chat = nil
      assert_enqueued_with(job: LlmChatTimeoutJob, at: 180.seconds.from_now, queue: "timeouts") do
        chat = create(:llm_chat, deadline_at: 5.minutes.from_now)
      end

      assert_equal 180.seconds.from_now, chat.deadline_at
    end
  end

  test "#create! should preserve and schedule an earlier preview deadline" do
    freeze_time do
      chat = nil
      assert_enqueued_with(job: LlmChatTimeoutJob, at: 30.seconds.from_now) do
        chat = create(:llm_chat, purpose: :preview, deadline_at: 30.seconds.from_now)
      end

      assert_equal 30.seconds.from_now, chat.deadline_at
    end
  end

  test "#execute should retain usage and leave success pending output validation" do
    provider = LlmProvider::Openai.new(credential_data: { "api_key" => "test-key" })
    chat = create(:llm_chat)
    chat.context = provider.context
    chat.protocol = provider.protocol
    chat.ask_later("Find one item.")
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return(body: file_fixture("llm_transcripts/completed.json").read, headers: { "Content-Type" => "application/json" })

    assert_equal '{"items":[]}', chat.execute(provider: provider).content

    assert chat.reload.running?
    assert_equal 1, chat.ruby_llm_usages.count
    assert_requested request, times: 1
  end

  [false, true].each do |timeout_job_runs|
    test "#execute should reject late output with timeout job running: #{timeout_job_runs}" do
      freeze_time do
        provider = LlmProvider::Openai.new(credential_data: { "api_key" => "test-key" })
        chat = create(:llm_chat, deadline_at: 10.seconds.from_now)
        chat.context = provider.context
        chat.protocol = provider.protocol
        chat.ask_later("Find one item.")
        request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do
          travel 10.seconds
          LlmChatTimeoutJob.perform_now(chat.id) if timeout_job_runs
          { body: file_fixture("llm_transcripts/completed.json").read, headers: { "Content-Type" => "application/json" } }
        end

        assert_raises(LlmExecution::DeadlineExceeded) { chat.execute(provider: provider) }

        assert chat.reload.interrupted?
        assert_equal "deadline_exceeded", chat.error_category
        assert_equal 1, chat.ruby_llm_usages.count
        assert_equal "succeeded", chat.ruby_llm_usages.sole.status
        assert_not chat.finish!(status: :succeeded)
        assert_requested request, times: 1
      end
    end
  end

  test "#execute should interrupt an overdue chat without calling the provider" do
    provider = LlmProvider::Openai.new(credential_data: { "api_key" => "test-key" })
    chat = create(:llm_chat, deadline_at: 1.second.ago)
    chat.context = provider.context
    chat.protocol = provider.protocol
    chat.ask_later("Find one item.")

    assert_raises(LlmExecution::DeadlineExceeded) { chat.execute(provider: provider) }

    assert chat.reload.interrupted?
    assert_empty chat.ruby_llm_usages
    assert_not_requested :post, "https://api.openai.com/v1/responses"
  end

  test "#execute should reject a stale worker after another worker settles the chat" do
    provider = LlmProvider::Openai.new(credential_data: { "api_key" => "test-key" })
    chat = create(:llm_chat)
    LlmChat.find(chat.id).finish!(status: :failed, error_category: "provider_error")

    assert_raises(ArgumentError) { chat.execute(provider: provider) }

    assert chat.reload.failed?
    assert_not_requested :post, "https://api.openai.com/v1/responses"
  end

  test "#execute should settle an expired chat even when the HTTP request fails" do
    freeze_time do
      provider = LlmProvider::Openai.new(credential_data: { "api_key" => "test-key" })
      chat = create(:llm_chat, deadline_at: 10.seconds.from_now)
      chat.context = provider.context
      chat.protocol = provider.protocol
      chat.ask_later("Find one item.")
      request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do
        travel 10.seconds
        raise Net::ReadTimeout
      end

      assert_raises(Faraday::TimeoutError) { chat.execute(provider: provider) }

      assert chat.reload.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
      assert_equal "failed", chat.ruby_llm_usages.sole.status
      assert_requested request, times: 1
    end
  end

  test "#complete! should preserve success when a stale worker reports failure" do
    chat = create(:llm_chat)
    stale = LlmChat.find(chat.id)

    freeze_time do
      assert chat.complete!
      assert_not stale.fail!(RuntimeError.new("private provider detail"))
      assert stale.reload.succeeded?
      assert_equal Time.current, stale.finished_at
      assert_nil stale.error_category
    end
  end

  test "#fail! should classify the exception and prevent subsequent completion" do
    chat = create(:llm_chat)

    assert chat.fail!(ArgumentError.new("private provider detail"))
    assert_not chat.complete!
    assert chat.reload.failed?
    assert_equal "ArgumentError", chat.error_category
    assert_not_includes chat.attributes.to_json, "private provider detail"
  end

  test "#complete! should interrupt a chat at its deadline" do
    chat = create(:llm_chat)

    travel_to chat.deadline_at, with_usec: true do
      assert_not chat.complete!
      assert chat.reload.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
      assert_not chat.fail!(RuntimeError.new("late failure"))
    end
  end

  test "#fail! should give an expired deadline precedence over the reported error" do
    chat = create(:llm_chat)

    travel_to chat.deadline_at, with_usec: true do
      assert_not chat.fail!(ArgumentError.new("late failure"))

      assert chat.reload.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
      assert_equal Time.current, chat.finished_at
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
    travel_to Time.zone.local(2026, 9, 15) do
      expired = create(:llm_chat, created_at: Time.zone.local(2026, 7, 15))
      recent = create(:llm_chat, created_at: Time.zone.local(2026, 7, 15, 0, 0, 1))

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
