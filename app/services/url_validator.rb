class UrlValidator
  def self.valid?(url)
    return false unless url.present?

    uri = URI.parse(url.strip)
    %w[http https].include?(uri.scheme)
  rescue URI::InvalidURIError
    false
  end

  def self.validation_regex
    URI::DEFAULT_PARSER.make_regexp(%w[http https])
  end
end