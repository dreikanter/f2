class LlmClient
  module Adapter
    # Basic abstraction for an LLM provider adapter
    class Base
      # Provider-specific request params that enable web access, deep-merged
      # into the request via `with_params`.
      def web_params(_model)
        raise NotImplementedError, "#{self.class} must implement #web_params"
      end

      # Enables web access on a RubyLLM chat however the provider realizes it.
      # The default is provider-hosted server tools injected as request params;
      # providers without server web override this (e.g. client-side tools).
      def apply_web(chat, model)
        params = web_params(model)
        chat.with_params(**params) if params.present? && chat.respond_to?(:with_params)
      end

      # Whether the provider can return grounded, schema-valid JSON from a
      # single web+schema call through RubyLLM. When false, extraction falls
      # back to two calls (gather with web, then structure with schema).
      def combined_extraction?
        false
      end

      # Hook to repair a provider's structured-output text before JSON parsing.
      # The default trusts the provider to return clean JSON; providers that
      # wrap it (e.g. Moonshot's markdown fences) override this.
      def unwrap_json(text)
        text
      end
    end
  end
end
