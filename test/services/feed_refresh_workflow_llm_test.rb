require "test_helper"

class FeedRefreshWorkflowLlmTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "#execute should persist validated posts and native usage linked to its event" do
    create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)
    request = stub_response do |http|
      chat = feed.llm_chats.sole
      assert chat.running?
      assert_equal chat, refresh_event.references.sole
      assert_equal "started", refresh_event.metadata.fetch("status")
      assert_equal feed.ai_model, JSON.parse(http.body).fetch("model")
    end

    assert_no_difference "LlmUsage.count" do
      assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
        perform_enqueued_jobs(only: FeedRefreshJob) { FeedSchedulerJob.perform_now }
      end
    end

    chat = feed.llm_chats.sole
    assert chat.succeeded?
    assert_equal feed.user, chat.user
    assert_equal credential, chat.ai_credential
    assert_equal "openai", chat.requested_provider
    assert_equal feed.ai_model, chat.requested_model
    assert_equal "llm", chat.profile_key
    assert_equal "scheduled_run", chat.purpose
    assert_equal %w[system user assistant], chat.messages.map(&:role)
    usage = chat.ruby_llm_usages.sole
    assert_equal "succeeded", usage.status
    assert_equal 40, usage.input_tokens
    assert_equal 20, usage.output_tokens
    assert usage.total_cost.positive?
    assert_equal chat.messages.last, usage.message
    assert_equal "completed", refresh_event.metadata.fetch("status")
    assert_equal [chat], refresh_event.references.grep(LlmChat)
    assert_equal feed.posts.to_a, refresh_event.references.grep(Post)
    post = feed.posts.sole
    assert post.enqueued?
    assert_includes post.content, "A source post"
    assert_equal "https://example.com/post", post.source_url
    assert_equal item, feed.feed_entries.sole.raw_data
    assert_equal 0, feed.reload.consecutive_failures
    assert_requested request, times: 1
  end

  test "#execute should settle empty valid output without publication" do
    request = stub_response(output: '{"items":[]}')

    assert_no_enqueued_jobs(only: PostPublishJob) { FeedRefreshWorkflow.new(feed).execute }

    assert feed.llm_chats.sole.succeeded?
    assert_equal "completed", refresh_event.metadata.fetch("status")
    assert_empty feed.feed_entries
    assert_requested request, times: 1
  end

  test "#execute should reject invalid output while retaining native usage" do
    request = stub_response(output: '{"items":[{"body":"missing source_url"}]}')

    assert_no_publication do
      assert_raises(Processor::LlmProcessor::InvalidOutput) { FeedRefreshWorkflow.new(feed).execute }
    end

    chat = feed.llm_chats.sole
    assert chat.failed?
    assert_equal "Processor::LlmProcessor::InvalidOutput", chat.error_category
    assert_equal "succeeded", chat.ruby_llm_usages.sole.status
    assert_equal [chat], refresh_event.references
    assert_equal "failed", refresh_event.metadata.fetch("status")
    assert_requested request, times: 1
  end

  test "#perform should report provider failures once without exposing details in the event" do
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(status: 429, body: { error: { message: "private provider detail", type: "rate_limit_error" } })
    reports = capture_error_reports do
      assert_no_publication { FeedRefreshJob.perform_now(feed.id) }
    end
    report = reports.sole

    chat = feed.llm_chats.sole
    assert chat.failed?
    assert_equal report.error.cause.class.name, chat.error_category
    assert_equal "failed", chat.ruby_llm_usages.sole.status
    assert_equal [chat], refresh_event.references
    assert_equal "failed", refresh_event.metadata.fetch("status")
    assert_not_includes refresh_event.to_json, "private provider detail"
    assert_kind_of RubyLLM::Error, report.error.cause
    assert_equal feed.id, report.context[:feed_id]
    assert report.handled?
    assert_includes report.error.cause.message, "private provider detail"
    assert credential.reload.active?
    assert_requested request, times: 1
  end

  test "#execute should reject incomplete output even when its JSON is valid" do
    response = completed_response
    response.merge!("status" => "incomplete", "incomplete_details" => { "reason" => "max_output_tokens" })
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

    assert_no_publication do
      assert_raises(Loader::Error) { FeedRefreshWorkflow.new(feed).execute }
    end

    assert feed.llm_chats.sole.failed?
    assert_equal "failed", refresh_event.metadata.fetch("status")
    assert_requested request, times: 1
  end

  test "#execute should interrupt late output before the timeout job runs" do
    freeze_time do
      request = stub_response { travel LlmChat::TIMEOUT }

      assert_no_publication do
        assert_raises(Loader::Error) { FeedRefreshWorkflow.new(feed).execute }
      end

      chat = feed.llm_chats.sole
      assert chat.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
      assert_equal "succeeded", chat.ruby_llm_usages.sole.status
      assert_equal [chat], refresh_event.references
      assert_equal "failed", refresh_event.metadata.fetch("status")
      assert_requested request, times: 1
    end
  end

  test "#execute should reject output after the timeout job interrupts its chat" do
    freeze_time do
      request = stub_response do
        travel LlmChat::TIMEOUT
        LlmChatTimeoutJob.perform_now(feed.llm_chats.sole.id)
      end

      assert_no_publication do
        assert_raises(Loader::Error) { FeedRefreshWorkflow.new(feed).execute }
      end

      chat = feed.llm_chats.sole
      assert chat.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
      assert_equal "succeeded", chat.ruby_llm_usages.sole.status
      assert_equal [chat], refresh_event.references
      assert_equal "failed", refresh_event.metadata.fetch("status")
      assert_requested request, times: 1
    end
  end

  test "#execute should prevent a stale worker from publishing after another terminal outcome" do
    request = stub_response do
      feed.llm_chats.sole.fail!(LlmExecution::ToolLimitExceeded.new)
    end

    assert_no_publication do
      assert_raises(Loader::Error) { FeedRefreshWorkflow.new(feed).execute }
    end

    chat = feed.llm_chats.sole
    assert chat.failed?
    assert_equal "LlmExecution::ToolLimitExceeded", chat.error_category
    assert_equal "succeeded", chat.ruby_llm_usages.sole.status
    assert_equal "failed", refresh_event.metadata.fetch("status")
    assert_requested request, times: 1
  end

  test "#execute should leave an abandoned chat to its timeout and retain its event link" do
    abandoned = create(:event, type: "feed_refresh", subject: feed, user: feed.user, metadata: { status: "started" })
    chat = create(:llm_chat, feed: feed, user: feed.user, ai_credential: credential)
    abandoned.event_references.create!(reference: chat)
    request = stub_response(output: '{"items":[]}')

    FeedRefreshWorkflow.new(feed).execute

    assert chat.reload.running?
    assert_equal "interrupted", abandoned.reload.metadata.fetch("status")
    assert_equal [chat], abandoned.references
    completed = feed.events.where(type: "feed_refresh").where.not(id: abandoned.id).sole
    assert_equal [feed.llm_chats.where.not(id: chat.id).sole], completed.references
    travel_to chat.deadline_at, with_usec: true do
      LlmChatTimeoutJob.perform_now(chat.id)
    end
    assert chat.reload.interrupted?
    assert_equal "deadline_exceeded", chat.error_category
    assert_equal [chat], abandoned.references
    assert_requested request, times: 1
  end

  private

  def credential
    @credential ||= create(:ai_credential, :active, credential_data: { "api_key" => "refresh-test-key" })
  end

  def feed
    @feed ||= begin
      model = RubyLLM::Models.new([]).load_from_json.find("gpt-5-nano", provider: "openai")
      RubyLLM::ActiveRecord::Model.from_llm(model).save!
      create(:feed, :enabled, user: credential.user, ai_credential: credential, ai_model: "gpt-5-nano",
                    feed_profile_key: "llm", params: { "prompt" => "A daily roundup" },
                    search_credential: nil, consecutive_failures: 1)
    end
  end

  def refresh_event
    feed.events.where(type: "feed_refresh").sole
  end

  def item
    { "body" => "A source post", "source_url" => "https://example.com/post", "title" => "",
      "supplementary" => [], "images" => [], "published_at" => "" }
  end

  def completed_response(output: { items: [item] }.to_json)
    JSON.parse(file_fixture("llm_transcripts/completed.json").read).tap do |response|
      response["output"].last["content"].first["text"] = output
    end
  end

  def stub_response(output: { items: [item] }.to_json)
    stub_request(:post, "https://api.openai.com/v1/responses")
      .with(headers: { "Authorization" => "Bearer refresh-test-key" })
      .to_return do |http|
        yield http if block_given?
        { body: completed_response(output: output).to_json, headers: { "Content-Type" => "application/json" } }
      end
  end

  def assert_no_publication(&block)
    assert_no_difference ["FeedEntry.count", "FeedEntryUid.count", "Post.count"] do
      assert_no_enqueued_jobs(only: PostPublishJob, &block)
    end
  end
end
