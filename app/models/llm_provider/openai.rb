module LlmProvider
  # Configures OpenAI SDK contexts and Responses requests.
  class Openai < Base
    def self.web_search_call_count(calls)
      Array(calls).count { |call| call["type"] == "web_search_call" }
    end

    def protocol
      :responses
    end

    def request_options(tool_call_limit:, output_token_limit:)
      {
        max_tool_calls: tool_call_limit,
        max_output_tokens: output_token_limit
      }
    end

    private

    def configure(config)
      config.openai_api_key = credential_data&.fetch("api_key", nil)
    end
  end
end
