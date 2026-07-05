require "resolv"
urls = ["https://cdn.example.com/ok.png", "https://example.com/normal.png", "https://10.example.com/"]
urls.each do |u|
  s = u.to_s.strip
  begin
    uri = URI.parse(s)
    cond = uri.is_a?(URI::HTTP) && uri.hostname.present? && uri.userinfo.nil?
    ph = nil
    ph = PublicUrl.private_host?(uri.hostname) if cond
    puts format("%-34s parse_ok cond=%-6s host=%-20s private_host?=%s => safe?=%s",
                u, cond, uri.hostname.inspect, ph.inspect, PublicUrl.safe?(u))
  rescue => e
    puts format("%-34s RAISED %s: %s => safe?=%s", u, e.class, e.message, PublicUrl.safe?(u))
  end
end
