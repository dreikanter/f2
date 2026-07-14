class LlmClient
  module Adapter
    # Basic abstraction for an LLM provider adapter.
    class Base
      # Provider-specific request params that remain necessary alongside the
      # shared client-side web tools.
      def web_params(_model)
        {}
      end

      # Every provider uses the same credential-backed search and fetch tools.
      # Adapters may still add provider-specific request params, but search never
      # delegates to a provider-hosted implementation. The search tool arrives
      # prebuilt: LlmClient owns its credential/attribution context.
      def apply_web(chat, model, search_tool:)
        params = web_params(model)
        chat.with_params(**params) if params.present?
        chat.with_tool(search_tool)
        chat.with_tool(LlmClient::Tools::WebFetch)
      end

      # True when one web+schema call returns grounded, schema-valid JSON; false
      # falls back to gather-then-structure (two calls).
      def combined_extraction?
        false
      end

      # Repairs structured-output text before JSON parsing. Default trusts clean
      # JSON; providers that wrap it (Moonshot fences) override.
      def unwrap_json(text)
        text
      end
    end
  end
end
