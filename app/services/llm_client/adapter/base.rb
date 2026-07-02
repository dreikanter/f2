class LlmClient
  module Adapter
    # Interface every provider adapter implements.
    class Base
      # Provider-specific request params that enable web access, deep-merged
      # into the request via `with_params`.
      def web_params(_model)
        raise NotImplementedError, "#{self.class} must implement #web_params"
      end
    end
  end
end
