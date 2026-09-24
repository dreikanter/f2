module LlmProvider
  # Provider-specific SDK configuration bound to a credential snapshot.
  class Base
    # Capture credentials so later edits cannot change this provider instance.
    # @param credential_data [Hash] provider-specific authentication fields
    # @return [Base] provider client bound to a copy of the supplied credentials
    def initialize(credential_data:)
      @credential_data = credential_data.deep_dup
    end

    # Bound HTTP waits and disable retries in an isolated SDK context.
    # @return [RubyLLM::Context] SDK context using this client's credentials
    def context
      RubyLLM.context do |config|
        configure(config)
        config.max_retries = 0
        config.request_timeout = 180
      end
    end

    # Select the API format RubyLLM uses to send requests and read responses.
    # @abstract Subclasses select the protocol.
    # @return [Symbol, nil] protocol override, or nil for the SDK default
    def protocol
      raise NotImplementedError, "Subclasses must implement #protocol"
    end

    # @return [Array<Symbol>] provider-hosted tools available for feed retrieval
    def retrieval_tools
      [:web_search]
    end

    # Translate execution limits into provider-specific request options.
    # @abstract Subclasses supply the provider's options.
    # @param tool_call_limit [Integer] maximum additional hosted-tool calls
    # @param output_token_limit [Integer] maximum output tokens per request
    # @return [Hash] options to merge into the SDK request configuration
    def request_options(tool_call_limit:, output_token_limit:)
      raise NotImplementedError, "Subclasses must implement #request_options"
    end

    private

    attr_reader :credential_data

    def configure(config)
      raise NotImplementedError, "Subclasses must implement #configure"
    end
  end
end
