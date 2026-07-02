class LlmClient
  module Adapter
    # OpenRouter enables web access through its cross-model web plugin.
    # `require_parameters` routes only to upstreams that honor the request's
    # structured-output parameters.
    class OpenRouter < Base
      def web_params(_model)
        {
          plugins: [{ id: "web" }],
          provider: { require_parameters: true }
        }
      end
    end
  end
end
