class LlmClient
  module Adapter
    class OpenAi < Base
      # OpenAI's reasoning models reason by default, and OpenAI rejects function
      # tools alongside reasoning on the chat-completions endpoint RubyLLM
      # speaks. Scoped to tool-enabled calls, so structuring keeps its reasoning.
      def web_params(_model)
        { reasoning_effort: "none" }
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
