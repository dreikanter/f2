module LlmProvider
  # Configures OpenAI SDK contexts and Responses requests.
  class Openai < Base
    def protocol
      :responses
    end

    def request_options(tool_call_limit:)
      { max_tool_calls: tool_call_limit }
    end

    private

    def configure(config)
      config.openai_api_key = credential_data&.fetch("api_key", nil)
    end
  end
end
