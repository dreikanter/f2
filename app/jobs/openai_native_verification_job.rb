# Manual, temporary provider evidence for #1722. Remove after live verification.
class OpenaiNativeVerificationJob < ApplicationJob
  include RecordsJobRun
  include RunsAsMaintenanceJob

  CREDENTIAL_NAME = "OpenaiNativeVerification".freeze
  MODEL = "gpt-5-mini".freeze
  PROMPT = "Search the web for the latest Ruby release on ruby-lang.org. Return one short item with its source URL.".freeze
  EVENT_PREFIX = "job.openai_native_verification".freeze

  def self.display_name = "OpenAI Native Verification"

  def self.description
    "Staging only. Uses your active OpenAI credential named #{CREDENTIAL_NAME} with #{MODEL} and native search. " \
      "Run authorizes one paid request, up to four hosted tool calls and 16,384 output tokens, with no retries. " \
      "Copy the report from the run details. No entries or posts are saved."
  end

  def self.runnable_arguments(user) = [user]

  def perform(user)
    return unless job_run
    return skip("This verification runs only on staging.") unless Rails.env.staging?

    credential = user.ai_credentials.find_by(provider: "openai", display_name: CREDENTIAL_NAME)
    return skip("Create or rename an active OpenAI credential to #{CREDENTIAL_NAME} on your account.") unless credential&.active?
    return unless claim_request

    feed = Feed.new(user: user, ai_credential: credential, ai_model: MODEL,
                    feed_profile_key: "llm", params: { "prompt" => PROMPT })
    verify(feed)
  end

  private

  # A redelivered job must not spend again, even if its first worker disappeared.
  def claim_request
    job_run.with_lock do
      return false if job_run.events.exists?(type: "#{EVENT_PREFIX}.started")

      record_event(type: "#{EVENT_PREFIX}.started", message: "One live request authorized. This run will not retry.")
      true
    end
  end

  def skip(reason)
    record_event(type: "#{EVENT_PREFIX}.skipped", message: reason, level: :warning, result: "SKIP")
  end

  def verify(feed)
    @report = { checked_at: Time.current.iso8601, revision: Config.app_revision,
                provider: "openai", model: feed.ai_model, credential_id: feed.ai_credential_id,
                ruby_llm_version: RubyLLM::VERSION, requests: 0, checks: {} }
    loader = Loader::LlmLoader.new(feed, purpose: :preview)
    content = loader.load do |chat|
      chat.before_request do |payload|
        raise LlmExecution::RequestLimitExceeded if @report[:requests] == 1

        @report[:requests] += 1
        payload = payload.deep_stringify_keys
        @report[:request] = payload.slice("model", "max_tool_calls", "max_output_tokens", "text")
        @report[:request]["tools"] = payload.fetch("tools").map { |tool| tool.slice("type") }
      end
    end
    schema = @report.fetch(:request).dig("text", "format", "schema")
    @report[:checks][:strict_output] = JSONSchemer.schema(schema).valid?(JSON.parse(content))
    result = feed.processor_instance(content).process
    @report[:checks][:processor_output] = true
    @report[:item_count] = result.entries.size
  rescue StandardError => error
    Rails.error.report(error)
    cause = error.cause || error
    @report[:error_class] = cause.class.name
    if cause.is_a?(RubyLLM::Error)
      @report[:http_status] = cause.response&.status
      @report[:provider_error] = provider_error(cause.response)
    end
  ensure
    finish_report(loader&.chat)
  end

  def provider_error(response)
    body = response&.body
    body = JSON.parse(body) if body.is_a?(String)
    body["error"].slice("type", "code", "param") if body.is_a?(Hash) && body["error"].is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def finish_report(chat)
    if chat
      response = chat.messages.where(role: "assistant").last
      searches = response&.server_tool_calls.to_a.select { |call| call.type == "web_search_call" }
      @report[:completed_searches] = searches.count { |call| call.raw.deep_stringify_keys["status"] == "completed" }
      @report[:checks][:native_search] = @report[:completed_searches].positive?
      usages = chat.ruby_llm_usages.to_a
      @report[:usage] = usages.map do |usage|
        usage.attributes.slice("provider", "model", "status", "input_tokens", "output_tokens", "thinking_tokens", "total_cost")
      end
      @report[:checks][:native_usage] = usages.one? && usages.first.status == "succeeded" && usages.first.usage_available?
      @report[:finish_reason] = response&.finish_reason
      passed = @report[:error_class].nil? && @report[:checks].values_at(:strict_output, :processor_output, :native_search, :native_usage).all?
      chat.timeout!
      settled = chat.finish!(status: passed ? :succeeded : :failed, error_category: passed ? nil : "verification_failed")
      @report[:checks][:completed_before_deadline] = settled
      @report[:chat_id] = chat.id
      @report[:chat_status] = chat.reload.status
    end
    @report[:result] = passed && settled ? "PASS" : "FAIL"
    @report[:cost_note] = "SDK token estimate in USD; hosted search charges are not included. Null means unknown."
    record_event(type: "#{EVENT_PREFIX}.completed", message: "Native OpenAI verification: #{@report[:result]}",
                 level: @report[:result] == "PASS" ? :info : :warning, **@report)
  end
end
