urls = [
  "https://cdn.example.com/ok.png",
  "https://example.com/normal.png",
  "https://xn--r8jz45g.jp/img.png",
  "https://10.example.com/",
  "https://localhost.example.com/",
]
urls.each do |u|
  uri = URI.parse(u.strip)
  begin
    ip = IPAddr.new(uri.hostname.downcase)
    ipinfo = "IP=#{ip} priv=#{ip.private?} lb=#{ip.loopback?}"
  rescue => e
    ipinfo = "IPAddr #{e.class}"
  end
  puts format("%-34s safe?=%-6s %s", u, PublicUrl.safe?(u), ipinfo)
end
