class LlmClient
  module Adapter
    class Anthropic < Base
      def native_search_transport
        AnthropicSearch
      end

      def unsupported_native_search?(error, model:)
        detail = error_detail(error)
        return false unless detail.is_a?(Hash) && detail["type"] == "invalid_request_error"

        message = detail["message"].to_s
        return true if message.match?(/\AWeb search is (?:not enabled|disabled)(?:[.\s]|$)/i)

        target = /(?:(?:this |the selected )?model\b|['"]?#{Regexp.escape(model)}['"]?(?:[.\s]|$))/i
        message.match?(/\A(?:Tool ['"]?web_search['"]?|Web search) is not supported (?:with|for|by) #{target}/i)
      end

      def unsupported_schema?(error)
        error.message.match?(/\A(?:output_config\.format|Structured outputs?) (?:is|are) not supported (?:for|with|by|on) (?:this |the selected )?model\b/i)
      end

      # Anthropic can complete a structured extraction while driving function
      # tools, so gathering and structuring stay in one call.
      def combined_extraction?
        true
      end
    end
  end
end
