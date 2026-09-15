module AiCredentialValidator
  # Sanitized authentication failure with a category and optional HTTP status.
  class Error < StandardError
    attr_reader :category, :status

    def initialize(message, category:, status: nil)
      @category = category
      @status = status
      super(message)
    end

    def invalid_key?
      category == :invalid_key
    end

    def details
      {
        error: message,
        category: category,
        status: status
      }.compact
    end
  end
end
