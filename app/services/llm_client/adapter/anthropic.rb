class LlmClient
  module Adapter
    # Anthropic enables web access through provider-hosted server tools. Citations
    # are disabled because they conflict with structured output.
    class Anthropic
      def web_params(_model)
        {
          tools: [
            { type: "web_search_20260209", name: "web_search" },
            { type: "web_fetch_20260209", name: "web_fetch", citations: { enabled: false } }
          ]
        }
      end
    end
  end
end
