module AiCredentialValidator
  # Provider-specific credential checks bound to a snapshot of the supplied fields.
  class Base
    # @param credential_data [Hash] provider-specific authentication fields
    def initialize(credential_data:)
      @credential_data = credential_data.deep_dup
    end

    # @abstract Validate the provider's credential fields without making requests.
    # @return [Array<String>] validation messages, empty when the fields are valid
    def errors
      raise NotImplementedError, "Subclasses must implement #errors"
    end

    # @abstract Check authentication without an inference request.
    # @return [Boolean] true when the provider accepts the credentials
    # @raise [AiCredentialValidator::Error] when authentication cannot be confirmed
    def validate!
      raise NotImplementedError, "Subclasses must implement #validate!"
    end

    private

    attr_reader :credential_data
  end
end
