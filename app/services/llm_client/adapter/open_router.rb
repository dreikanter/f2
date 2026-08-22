class LlmClient
  module Adapter
    class OpenRouter < Base
      # OpenRouter picks which upstream serves a model, and an upstream that
      # doesn't implement a parameter drops it silently instead of failing. This
      # narrows routing to upstreams that honor everything the request carries:
      # the JSON schema when structuring, the client-side tools when gathering.
      # Without it a structuring call can land where `response_format` is
      # ignored and come back as prose or a bare list — a schema failure no
      # payload repair can rescue. Web search and fetch are supplied by the
      # shared client-side tools either way.
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
