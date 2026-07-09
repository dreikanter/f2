class LlmClient
  module Adapter
    # Basic abstraction for an LLM provider adapter
    class Base
      # Provider-specific request params that enable web access, deep-merged
      # into the request via `with_params`.
      def web_params(_model)
        raise NotImplementedError, "#{self.class} must implement #web_params"
      end

      # Enables web access on a chat, however the provider realizes it. Default
      # injects server-tool params; providers without server web override
      # (e.g. client-side tools).
      def apply_web(chat, model)
        params = web_params(model)
        chat.with_params(**params) if params.present?
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
