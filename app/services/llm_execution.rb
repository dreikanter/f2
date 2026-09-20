# Runs a staged SDK chat within one extraction's execution budget.
class LlmExecution
  MAX_REQUESTS = 4
  MAX_OUTPUT_TOKENS = 16_384
  MAX_TOOL_CALLS = 16

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

    raise ArgumentError, "Concurrent local tools are not supported" if chat.concurrency

    @deadline_at = deadline_at
    @requests = 0
    @tool_calls = 0
    @chat = chat
    @provider = provider
    @output_token_limit = [MAX_OUTPUT_TOKENS, @chat.model.max_output_tokens, @chat.max_output_tokens].compact.min
    @chat.with_fallbacks(nil).with_compaction(false)
    @chat.with_max_output_tokens(@output_token_limit)
    @chat.before_tool_call { check_deadline! }
  end

  # @return [RubyLLM::Message] final SDK response
  def call
    check_deadline!
    until @chat.complete?
      raise RequestLimitExceeded if @requests >= MAX_REQUESTS
      raise ToolLimitExceeded if @tool_calls >= MAX_TOOL_CALLS

      check_deadline!
      options = @provider.request_options(
        tool_call_limit: MAX_TOOL_CALLS - @tool_calls,
        output_token_limit: @output_token_limit
      )
      @chat.with_provider_options(@chat.provider_options.symbolize_keys.merge(options))
      @requests += 1
      response = @chat.generate
      @tool_calls += response.server_tool_calls.size
      check_deadline!
      raise ToolLimitExceeded if @tool_calls > MAX_TOOL_CALLS
      raise ToolLimitExceeded if response.finish_reason == :max_tool_calls

      return response if @chat.complete?

      @chat.run_tools
      check_deadline!
    end
    @chat.messages.last
  end

  private

  def check_deadline!
    raise DeadlineExceeded if Time.current >= @deadline_at
  end
end
