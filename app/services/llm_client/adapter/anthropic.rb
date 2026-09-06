class LlmClient
  module Adapter
    class Anthropic < Base
      def native_search_transport
        AnthropicSearch
      end

      def unsupported_native_search?(error, model:)
        AnthropicSearch.unsupported_search?(error, model: model)
      end

      def unsupported_schema?(error)
        error.message.match?(/\A(?:output_config\.format|Structured outputs?) (?:is|are) not supported (?:for|with|by|on) (?:this |the selected )?model\b/i)
      end

      # Anthropic can complete a structured extraction while driving function
      # tools, so gathering and structuring stay in one call.
      def combined_extraction?
        true
      end
    end
  end
end
