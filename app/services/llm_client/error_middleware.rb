class LlmClient
  class ErrorMiddleware < RubyLLM::ErrorMiddleware
    class MalformedResponse < ProviderError
      attr_reader :response

      def initialize(response)
        @response = response
        super("AI provider returned a malformed error response (HTTP #{response.status})")
      end
    end

    # Some SDK error parsers assume nested objects in provider error bodies.
    # Limit normalization to that parser, preserving the response and cause.
    def self.parse_error(provider:, response:)
      super
    rescue TypeError, NoMethodError
      raise unless response.status >= 400

      raise MalformedResponse.new(response)
    end
  end
end
