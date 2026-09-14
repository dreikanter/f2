module LlmProvider
  # Abstract client bound to a credential snapshot. Each provider interprets its
  # own fields for validation, SDK configuration, and model discovery.
  class Base
    # @param credential_data [Hash] provider-specific authentication fields
    # @return [Base] provider client bound to a copy of the supplied credentials
    def initialize(credential_data:)
      @credential_data = credential_data.deep_dup
    end

    # @abstract Validate the provider's credential fields without making requests.
    # @return [Array<String>] validation messages, empty when the fields are valid
    def credential_errors
      raise NotImplementedError, "Subclasses must implement #credential_errors"
    end

    # @abstract Check authentication without an inference request.
    # @return [Boolean] true when the provider accepts the credentials
    # @raise [LlmProvider::Error] when authentication cannot be confirmed
    def validate_credentials!
      raise NotImplementedError, "Subclasses must implement #validate_credentials!"
    end

    # @return [RubyLLM::Context] isolated SDK context using this client's credentials, with retries disabled
    def context
      RubyLLM.context do |config|
        configure(config)
        config.max_retries = 0
      end
    end

    # @abstract Implement provider model discovery.
    # @return [Array<String>] model IDs available to this client's credentials
    def models
      raise NotImplementedError, "Subclasses must implement #models"
    end

    private

    attr_reader :credential_data

    def configure(config)
      raise NotImplementedError, "Subclasses must implement #configure"
    end
  end
end
