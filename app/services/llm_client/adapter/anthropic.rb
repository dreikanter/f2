class LlmClient
  module Adapter
    # Anthropic enables web access through provider-hosted server tools. Citations
    # are disabled because they conflict with structured output.
    class Anthropic < Base
      def web_params(_model)
        {
          tools: [
            { type: "web_search_20260209", name: "web_search" },
            { type: "web_fetch_20260209", name: "web_fetch", citations: { enabled: false } }
          ]
        }
      end

      # Live-verified (plan-03): a single Anthropic call carrying both the
      # schema and the web server tools returns grounded, schema-valid JSON.
      def combined_extraction?
        true
      end
    end
  end
end
