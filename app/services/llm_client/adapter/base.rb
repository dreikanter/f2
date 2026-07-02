class LlmClient
  module Adapter
    # Basic abstraction for an LLM provider adapter
    class Base
      # Provider-specific request params that enable web access, deep-merged
      # into the request via `with_params`.
      def web_params(_model)
        raise NotImplementedError, "#{self.class} must implement #web_params"
      end
    end
  end
end
