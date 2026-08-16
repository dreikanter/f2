class LlmClient
  module Adapter
    class OpenAi < Base
      # OpenAI reports a key with no spend room left as a 429, the same status
      # it uses for throughput throttling; only the body tells them apart.
      SPENT_KEY_CODE = "insufficient_quota".freeze

      def dead_key?(error)
        error_code(error) == SPENT_KEY_CODE
      end

      # OpenAI's reasoning models reason by default, and OpenAI rejects function
      # tools alongside reasoning on the chat-completions endpoint RubyLLM
      # speaks. Scoped to tool-enabled calls, so structuring keeps its reasoning.
      def web_params(_model)
        { reasoning_effort: "none" }
      end

      # OpenAI completes a structured extraction while driving function tools,
      # so gathering and structuring stay in one call.
      def combined_extraction?
        true
      end

      # OpenAI's strict mode requires every key in `properties` to appear in
      # `required`, recursively; UNIVERSAL_OUTPUT_SCHEMA leaves most item keys
      # optional. Unconstrained the schema still shapes the response, and the
      # normalizer still validates what comes back.
      def schema_strict?
        false
      end
    end
  end
end
