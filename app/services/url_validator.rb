class UrlValidator
  def self.valid?(url)
    return false unless url.present?

    uri = URI.parse(url.strip)
    %w[http https].include?(uri.scheme)
  rescue URI::InvalidURIError
    false
  end
end
