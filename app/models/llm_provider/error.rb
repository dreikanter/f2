module LlmProvider
  # Sanitized provider failure consumed by AI operations. Carries a category and
  # optional HTTP status for failure handling and reporting.
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
