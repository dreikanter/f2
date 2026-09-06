class LlmClient
  module Adapter
    class OpenRouter < Base
      def native_search_transport
        OpenRouterSearch
      end

      def unsupported_native_search?(error, model:)
        return true if unsupported_tools?(error)

        detail = error_detail(error)
        return false unless detail
        return true if detail["param"] == "max_tool_calls" && detail["code"] == "unsupported_parameter"

        message = detail["message"].to_s
        return true if message.match?(/\ANo endpoints found that support the requested server tools\b/i)
        return true if message.match?(/\A(?:Web search|Server tools?) (?:is|are) (?:disabled|not enabled)\b/i)

        target = /(?:(?:this |the selected )?model\b|['"]?#{Regexp.escape(model)}['"]?(?:[.\s]|$))/i
        message.match?(/\A(?:Web search|Server tools?|Tool ['"]?openrouter:web_search['"]?) (?:is|are) not supported (?:with|for|by) #{target}/i)
      end

      def unsupported_schema?(error)
        OpenAi.new.unsupported_schema?(error)
      end

      # OpenRouter picks the upstream, and one that doesn't implement a
      # parameter drops it silently. This restricts routing to upstreams that
      # honor what the request carries: the schema when structuring, the tools
      # when gathering. Without it a structuring call can land where
      # `response_format` is ignored and reply with prose.
      ROUTING = { provider: { require_parameters: true } }.freeze

      def web_params(_model)
        ROUTING
      end

      def schema_params(_model)
        ROUTING
      end

      # OpenRouter also uses 404 when no upstream supports the requested tools.
      def capability_error_status?(error)
        super || error.response&.status == 404
      end

      def unsupported_tools?(error)
        super || error_detail(error)&.fetch("message", "").to_s.match?(/\ANo endpoints found that support (?:tool use|the requested tools)\b/i)
      end
    end
  end
end
