require "timeout"

# Runs a staged OpenAI chat within one extraction's execution budget.
class LlmNativeExecution
  TIMEOUT = 180.seconds
  MAX_REQUESTS = 4
  MAX_OUTPUT_TOKENS = 16_384
  MAX_TOOL_CALLS = 4

  class DeadlineExceeded < StandardError; end
  class RequestLimitExceeded < StandardError; end
  class ToolLimitExceeded < StandardError; end

  # @param chat [LlmChat] persisted chat with its initial prompt already staged
  # @param provider [LlmProvider::Openai] credential-bound provider
  def initialize(chat:, provider:)
    @deadline_at = [chat.deadline_at, chat.started_at + TIMEOUT].min
    @requests = 0
    @tool_calls = 0
    chat.protocol = :responses
    chat.with_context(provider.context)
    @chat = chat.to_llm
    @chat.with_model(chat.requested_model, provider: :openai, protocol: :responses)
    @chat.with_fallbacks(nil).with_compaction(false)
    @chat.with_max_output_tokens(MAX_OUTPUT_TOKENS)
  end

  # @return [RubyLLM::Message] final SDK response
  def call
    remaining = remaining_time
    Timeout.timeout(remaining, DeadlineExceeded) do
      until @chat.complete?
        raise RequestLimitExceeded if @requests >= MAX_REQUESTS
        raise ToolLimitExceeded if @tool_calls >= MAX_TOOL_CALLS

        remaining_time
        @chat.with_provider_options(max_tool_calls: MAX_TOOL_CALLS - @tool_calls)
        @requests += 1
        response = @chat.generate
        @tool_calls += response.server_tool_calls.size
        remaining_time
        raise ToolLimitExceeded if @tool_calls > MAX_TOOL_CALLS

        return response if @chat.complete?

        @chat.run_tools
      end
      @chat.messages.last
    end
  end

  private

  def remaining_time
    remaining = @deadline_at - Time.current
    raise DeadlineExceeded unless remaining.positive?

    remaining
  end
end
