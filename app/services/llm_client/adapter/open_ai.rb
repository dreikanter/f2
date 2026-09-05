class LlmClient
  module Adapter
    class OpenAi < Base
      def output_params
        { max_completion_tokens: MAX_OUTPUT_TOKENS }
      end

      def native_search?
        true
      end

      def unsupported_schema?(error)
        body = error.response&.body
        body = JSON.parse(body) if body.is_a?(String)
        detail = body.is_a?(Hash) ? body["error"] : nil
        return false unless detail.is_a?(Hash) && %w[response_format text.format text.format.type].include?(detail["param"])

        detail["code"] == "unsupported_parameter" ||
          detail["message"].to_s.match?(/\AInvalid parameter: '(?:response_format|text.format)' of type 'json_schema' is not supported with (?:this )?model\b/i)
      rescue JSON::ParserError
        false
      end

      # OpenAI reports every billing stop as a 429, the status it also uses for
      # throughput throttling, so only the body separates them. Each of these
      # needs someone to add credit or raise a cap; none clears on retry.
      # `insufficient_quota` is the older name and is still served.
      SPENT_KEY_CODES = %w[
        credit_balance_exhausted
        organization_spend_limit_exceeded
        project_spend_limit_exceeded
        organization_usage_limit_reached
        insufficient_quota
      ].freeze

      def dead_key?(error)
        error_codes(error).intersect?(SPENT_KEY_CODES)
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
