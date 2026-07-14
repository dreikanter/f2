class LlmClient
  module Adapter
    class OpenRouter < Base
      # Route only to upstreams that honor structured-output parameters. Web
      # search and fetch are supplied by the shared client-side tools.
      def web_params(_model)
        { provider: { require_parameters: true } }
      end
    end
  end
end
