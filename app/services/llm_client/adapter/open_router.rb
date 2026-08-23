class LlmClient
  module Adapter
    class OpenRouter < Base
      # OpenRouter picks the upstream, and one that doesn't implement a
      # parameter drops it silently. This restricts routing to upstreams that
      # honor what the request carries: the schema when structuring, the tools
      # when gathering. Without it a structuring call can land where
      # `response_format` is ignored and reply with prose. Web access still
      # comes from the shared client-side tools, not an OpenRouter plugin.
      ROUTING = { provider: { require_parameters: true } }.freeze

      def web_params(_model)
        ROUTING
      end

      def schema_params(_model)
        ROUTING
      end
    end
  end
end
