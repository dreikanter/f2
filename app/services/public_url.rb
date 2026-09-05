require "ipaddr"
require "socket"

# Guards URLs the app would fetch server-side (SSRF). Safe means an
# absolute http(s) URL to a public host; non-http schemes, embedded
# credentials, localhost, and private/loopback/link-local literals are
# rejected. Literals are canonicalized the way resolvers read them, so
# encoded forms (http://2130706433 = 127.0.0.1) can't sneak through. DNS
# names are not resolved here; a name pointing at a private address must
# be caught at the fetch layer.
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

  # The caller must pin this address to the connection, preserving the hostname
  # for Host and TLS verification. Validating DNS and then resolving again would
  # leave a rebinding window.
  def self.public_address(host)
    addresses = Socket.getaddrinfo(host, nil, Socket::AF_UNSPEC, Socket::SOCK_STREAM)
                      .map { |entry| IPAddr.new(entry[3]) }.uniq
    return unless addresses.any? && addresses.all? { |address| public_ip?(address) }

    addresses.first.to_s
  end
end
