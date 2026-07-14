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
      # delegates to a provider-hosted implementation.
      def apply_web(chat, model, search_provider:, search_credential:, refresh_event: nil)
        params = web_params(model)
        chat.with_params(**params) if params.present?
        chat.with_tool(
          LlmClient::Tools::WebSearch.new(
            provider: search_provider,
            credential: search_credential,
            refresh_event: refresh_event
          )
        )
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
