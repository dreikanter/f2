module LlmProvider
  # Provider-specific SDK configuration bound to a credential snapshot.
  class Base
    # @param credential_data [Hash] provider-specific authentication fields
    # @return [Base] provider client bound to a copy of the supplied credentials
    def initialize(credential_data:)
      @credential_data = credential_data.deep_dup
    end

    # @return [RubyLLM::Context] isolated SDK context using this client's credentials, with retries disabled
    def context
      RubyLLM.context do |config|
        configure(config)
        config.max_retries = 0
      end
    end

    # @abstract Select the SDK protocol for this provider.
    # @return [Symbol, nil] protocol override, or nil for the SDK default
    def protocol
      raise NotImplementedError, "Subclasses must implement #protocol"
    end

    # @abstract Translate shared execution limits into provider request options.
    # @param tool_call_limit [Integer] maximum additional hosted-tool calls
    # @return [Hash] options to merge into the SDK request configuration
    def request_options(tool_call_limit:)
      raise NotImplementedError, "Subclasses must implement #request_options"
    end

    private

    attr_reader :credential_data

    def configure(config)
      raise NotImplementedError, "Subclasses must implement #configure"
    end
  end
end
