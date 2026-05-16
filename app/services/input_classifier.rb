# Classifies a raw user input as :url, :handle, :query, or :malformed.
# Called once at the start of feed detection; matchers declare which shapes
# they accept. See specs/001-smart-feed-creation/research.md §10.
class InputClassifier
  HANDLE_REGEX = /\A@[A-Za-z0-9_]{1,30}(@[A-Za-z0-9.-]+)?\z/
  QUERY_MIN_LENGTH = 3
  QUERY_MAX_LENGTH = 200

  def self.classify(input)
    new(input).classify
  end

  def initialize(input)
    @input = input.to_s.strip
  end

  def classify
    return :malformed if malformed?
    return :url if url?
    return :handle if handle?
    return :query if query?

    :malformed
  end

  private

  attr_reader :input

  def malformed?
    input.empty? || input.length < 2
  end

  def url?
    uri = URI.parse(input)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def handle?
    input.match?(HANDLE_REGEX)
  end

  def query?
    input.length.between?(QUERY_MIN_LENGTH, QUERY_MAX_LENGTH)
  end
end
