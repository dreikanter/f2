# Interprets provider-specific usage fields for display.
class LlmUsageDetails
  def initialize(usage)
    @usage = usage
  end

  def tool_cost_unknown?
    @usage.message&.[](:server_tool_calls).present?
  end

  # @return [Integer, nil] search count, or nil for an unsupported provider
  def web_search_count
    case @usage.provider
    when "openai"
      calls = Array(@usage.message&.[](:server_tool_calls))
      calls.count { |call| call["type"] == "web_search_call" }
    end
  end
end
