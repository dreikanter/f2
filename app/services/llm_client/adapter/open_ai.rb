class LlmClient
  module Adapter
    class OpenAi < Base
      def output_params
        { max_completion_tokens: OutputLimit::DEFAULT }
      end

      def native_search_transport
        OpenAiResponses
      end

      def transport_for(ctx, web:, tools:)
        OpenAiResponses if ctx && ctx.responses_api != false
      end

      def unsupported_native_search?(error, model:)
        detail = error_detail(error)
        return false unless detail

        parameter = detail["param"].to_s
        return true if %w[tools tools[0].type max_tool_calls].include?(parameter) && detail["code"] == "unsupported_parameter"

        target = /(?:(?:this |the selected )?model\b|['"]?#{Regexp.escape(model)}['"]?(?:[.\s]|$))/i
        detail["message"].to_s.match?(/\A(?:Tool ['"]?web_search['"]?|Web search) is not supported (?:with|for|by) #{target}/i)
      end

      def unsupported_responses?(error)
        detail = error_detail(error)
        detail && detail["param"] == "model" &&
          detail["message"].to_s.match?(/\A(?:The |This )?model\b.*\b(?:is not supported|does not support)\b.*\b(?:Responses|v1\/responses)\b/i)
      end

      def unsupported_schema?(error)
        detail = error_detail(error)
        return false unless detail.is_a?(Hash) && %w[response_format text.format text.format.type].include?(detail["param"])

        detail["code"] == "unsupported_parameter" ||
          detail["message"].to_s.match?(/\AInvalid parameter: '(?:response_format|text.format)' of type 'json_schema' is not supported with (?:this )?model\b/i)
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
