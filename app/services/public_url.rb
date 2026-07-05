require "ipaddr"

# Guards model-supplied URLs the app would fetch server-side — attachment
# uploads at publish time and the client-side web-fetch tool. A URL is safe
# only if it is an absolute http(s) URL to a public host; non-http schemes,
# embedded credentials, localhost, and private/link-local ranges are rejected
# (server-side request forgery; spec 005 §8).
module PublicUrl
  # Ranges IPAddr's loopback?/private?/link_local? predicates don't cover:
  # "this host" and carrier-grade NAT.
  EXTRA_BLOCKED = [IPAddr.new("0.0.0.0/8"), IPAddr.new("100.64.0.0/10")].freeze

  def self.safe?(url)
    uri = URI.parse(url.to_s.strip)
    return false unless uri.is_a?(URI::HTTP) && uri.hostname.present? && uri.userinfo.nil?

    !private_host?(uri.hostname)
  rescue URI::InvalidURIError
    false
  end

  # `host` is a bracket-stripped hostname (URI#hostname), so IP literals parse
  # cleanly and a non-IP hostname falls through as allowed.
  def self.private_host?(host)
    host = host.downcase
    return true if host == "localhost" || host.end_with?(".localhost")

    ip = IPAddr.new(host)
    ip.loopback? || ip.private? || ip.link_local? || EXTRA_BLOCKED.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    false
  end
end
