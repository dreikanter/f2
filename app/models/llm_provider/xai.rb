module LlmProvider
  # Configures xAI SDK contexts and Responses requests.
  class Xai < Base
    def protocol
      :responses
    end

    def retrieval_tools
      [:web_search, :x_search]
    end

    def request_options(tool_call_limit:, output_token_limit:)
      # xAI bounds turns; one call per turn keeps the shared budget meaningful.
      {
        max_turns: tool_call_limit,
        parallel_tool_calls: false,
        max_output_tokens: output_token_limit
      }
    end

    private

    def configure(config)
      config.xai_api_key = credential_data&.fetch("api_key", nil)
    end
  end
end
