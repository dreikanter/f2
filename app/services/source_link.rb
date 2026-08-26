# Decides whether an input counts as a source URL and returns the URL to
# fetch. Explicit http(s) inputs pass as typed; http is never forced to
# https since some feeds are http-only. A bare dotted host gets https
# prepended. Anything else (a handle, free text, a non-http scheme)
# returns nil, which the entry flow reads as "offer the AI mode".
class SourceLink
  def self.canonical(input)
    new(input).canonical
  end

  def self.url?(input)
    !canonical(input).nil?
  end

  def initialize(input)
    @input = input.to_s.strip
  end

  # The URL to fetch for this input, or nil if it isn't a URL.
  def canonical
    return nil if @input.empty?

    uri = safe_parse(@input)
    return nil if uri.nil?
    return uri.host.present? ? @input : nil if uri.is_a?(URI::HTTP)
    return nil if non_http_scheme?(uri)

    scheme_fixed_url
  end

  private

  def safe_parse(string)
    URI.parse(string)
  rescue URI::InvalidURIError
    nil
  end

  # A real non-http scheme (mailto:, ftp:) is dotless. A dotted "scheme" is
  # a bare host:port (`example.com:8080` parses as scheme `example.com`),
  # which we still scheme-fix.
  def non_http_scheme?(uri)
    uri.scheme.present? && !uri.scheme.include?(".")
  end

  # Prepend https:// and accept only a host with an interior dot, so
  # `example.com` works but `r/x` and `.example` don't.
  def scheme_fixed_url
    fixed = "https://#{@input}"
    uri = safe_parse(fixed)
    uri.is_a?(URI::HTTP) && dotted_host?(uri.host) ? fixed : nil
  end

  def dotted_host?(host)
    host.present? && host.include?(".") && !host.start_with?(".") && !host.end_with?(".")
  end
end
