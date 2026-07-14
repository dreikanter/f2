class LlmClient
  module Adapter
    class Anthropic < Base
      # Anthropic can complete a structured extraction while driving function
      # tools, so gathering and structuring stay in one call.
      def combined_extraction?
        true
      end
    end
  end
end
