class LlmClient
  module Adapter
    # Basic abstraction for an LLM provider adapter
    class Base
      # Provider-specific request params that enable web access, deep-merged
      # into the request via `with_params`.
      def web_params(_model)
        raise NotImplementedError, "#{self.class} must implement #web_params"
      end

      # Whether the provider can return grounded, schema-valid JSON from a
      # single web+schema call through RubyLLM. When false, extraction falls
      # back to two calls (gather with web, then structure with schema).
      def combined_extraction?
        false
      end
    end
  end
end
