require "timeout"

# Runs a staged SDK chat within one extraction's execution budget.
class LlmExecution
  TIMEOUT = 180.seconds
  MAX_REQUESTS = 4
  MAX_OUTPUT_TOKENS = 16_384
  MAX_TOOL_CALLS = 4

  class DeadlineExceeded < StandardError; end
  class RequestLimitExceeded < StandardError; end
  class ToolLimitExceeded < StandardError; end

  # @param chat [RubyLLM::Chat] prepared SDK chat with its initial prompt staged
  # @param provider [LlmProvider::Base] provider responsible for request configuration
  # @param deadline_at [Time] extraction deadline, including any earlier preview limit
  def initialize(chat:, provider:, deadline_at:)
    unless chat.context&.config&.max_retries == 0
      raise ArgumentError, "Chat must use a provider context with retries disabled"
    end

    @deadline_at = [deadline_at, TIMEOUT.from_now].min
    @requests = 0
    @tool_calls = 0
    @chat = chat
    @provider = provider
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
        options = @provider.request_options(tool_call_limit: MAX_TOOL_CALLS - @tool_calls)
        @chat.with_provider_options(@chat.provider_options.merge(options))
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
