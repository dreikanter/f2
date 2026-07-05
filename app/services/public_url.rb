require "ipaddr"
require "socket"

# Guards model-supplied URLs the app would fetch server-side — attachment
# uploads at publish time and the client-side web-fetch tool. A URL is safe
# only if it is an absolute http(s) URL to a public host; non-http schemes,
# embedded credentials, localhost, and any address literal in a private,
# loopback, or link-local range are rejected (server-side request forgery;
# spec 005 §8).
#
# Address literals are canonicalized the way the HTTP client's resolver reads
# them, so encoded forms (decimal/hex/octal, e.g. http://2130706433 → 127.0.0.1)
# can't smuggle a private target past a plain string check. DNS names are not
# resolved here, so a name pointing at a private address is a residual gap best
# closed at the fetch layer (resolve-and-pin).
module PublicUrl
  # Addresses IPAddr's loopback?/private?/link_local? predicates don't cover:
  # "this host" (v4 0.0.0.0/8 and the v6 unspecified ::) and carrier-grade NAT.
  EXTRA_BLOCKED = [IPAddr.new("0.0.0.0/8"), IPAddr.new("100.64.0.0/10"), IPAddr.new("::")].freeze

  def self.safe?(url)
    uri = URI.parse(url.to_s.strip)
    return false unless uri.is_a?(URI::HTTP) && uri.hostname.present? && uri.userinfo.nil?

    host = uri.hostname.downcase.chomp(".")
    literal = literal_ips(host)
    return literal.all? { |ip| public_ip?(ip) } if literal.any?

    host != "localhost" && !host.end_with?(".localhost")
  rescue URI::InvalidURIError
    false
  end

  # Canonical IPs when the host is an address literal in any notation
  # (dotted/decimal/hex/octal/IPv6), resolved numerically without DNS; empty for
  # a DNS name.
  def self.literal_ips(host)
    Addrinfo.getaddrinfo(host, nil, nil, :STREAM, nil, Socket::AI_NUMERICHOST)
            .map { |info| IPAddr.new(info.ip_address) }.uniq
  rescue SocketError, IPAddr::Error
    []
  end

  def self.public_ip?(ip)
    ip = ip.native # unwrap IPv4-mapped IPv6 (::ffff:127.0.0.1) to its IPv4 form
    return false if ip.loopback? || ip.private? || ip.link_local?

    EXTRA_BLOCKED.none? { |range| range.include?(ip) }
  end
end
