# Recovers a JSON value from loose model output. Providers that don't enforce
# structured output natively can wrap JSON in Markdown fences or surrounding
# prose; this strips that noise and parses the outermost JSON span. It does not
# repair invalid JSON or reshape against a schema — shape validation stays with
# the caller. Raises when nothing parseable is present.
class SchemaHealer
  Error = Class.new(StandardError)

  FENCE = /```(?:json)?\s*(.+?)```/m

  def self.call(raw)
    return raw if raw.is_a?(Hash) || raw.is_a?(Array)

    text = raw.to_s
    JSON.parse(text)
  rescue JSON::ParserError
    embedded(text) || raise(Error, "no recoverable JSON in response")
  end

  def self.embedded(text)
    source = text[FENCE, 1] || text
    open_at = source.index(/[\[{]/)
    close_at = source.rindex(/[\]}]/)
    return if open_at.nil? || close_at.nil? || close_at <= open_at

    JSON.parse(source[open_at..close_at])
  rescue JSON::ParserError
    nil
  end

  private_class_method :embedded
end
