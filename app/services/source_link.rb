# Decides whether a Mode A input counts as a source URL and returns the URL to
# fetch, applying the silent scheme-fix from spec 005 §1:
#
# - An explicit `http(s)://` input is honored as typed — `http://` is never
#   forced to `https://`, since some feeds are http-only.
# - A bare, host-shaped input gets an `https://` scheme (`example.com` →
#   `https://example.com`). "Host-shaped" means the fix yields a dotted host, so
#   `r/x` never becomes `https://r/x` (host `r`) — a non-URL like that routes to
#   the AI bridge instead of dead-ending in the couldn't-reach state.
#
# Anything else (a handle, a few words, a non-http scheme like `mailto:`) is not
# a URL and returns nil, which the entry flow reads as "offer Mode B".
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

  # A real non-http scheme (`mailto:`, `ftp:`, `javascript:`) has a dotless
  # scheme. A dotted "scheme" is actually a bare `host:port` (`example.com:8080`
  # parses as scheme `example.com`), which we still want to scheme-fix.
  def non_http_scheme?(uri)
    uri.scheme.present? && !uri.scheme.include?(".")
  end

  # No usable scheme: prepend https:// and accept only if it yields a dotted host.
  def scheme_fixed_url
    fixed = "https://#{@input}"
    uri = safe_parse(fixed)
    uri.is_a?(URI::HTTP) && uri.host&.include?(".") ? fixed : nil
  end
end
