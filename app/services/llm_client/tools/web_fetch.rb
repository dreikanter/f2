require "ipaddr"

class LlmClient
  module Tools
    # Client-side retrieval for providers without usable server-side web access
    # (Moonshot/Kimi). The model supplies the URL, so this is an SSRF surface
    # (spec 005 §8): only absolute public http(s) URLs are fetched — non-http,
    # credentials, localhost, and private/link-local ranges are refused first.
    class WebFetch < RubyLLM::Tool
      description "Fetch the readable text of a public web page. Pass one absolute http(s) URL."
      param :url, desc: "Absolute http(s) URL of the page to fetch", required: true

      MAX_REDIRECTS = 3
      MAX_BYTES = 200_000
      MAX_TEXT = 8_000
      # Ranges IPAddr's loopback?/private?/link_local? predicates don't cover:
      # "this host" and carrier-grade NAT.
      EXTRA_BLOCKED = [IPAddr.new("0.0.0.0/8"), IPAddr.new("100.64.0.0/10")].freeze

      def execute(url:)
        uri = safe_uri(url)
        return { error: "Refused: pass one absolute public http(s) URL." } unless uri

        response = HttpClient.build(max_redirects: MAX_REDIRECTS).get(uri.to_s)
        return { error: "HTTP #{response.status}" } unless response.success?

        { content: readable_text(response.body) }
      rescue HttpClient::Error => e
        { error: e.message }
      end

      private

      def safe_uri(url)
        uri = URI.parse(url.to_s.strip)
        return unless uri.is_a?(URI::HTTP) && uri.hostname.present? && uri.userinfo.nil?
        return if private_host?(uri.hostname)

        uri
      rescue URI::InvalidURIError
        nil
      end

      # `host` is a bracket-stripped hostname (URI#hostname), so IP literals
      # parse cleanly and a non-IP hostname falls through as allowed.
      def private_host?(host)
        host = host.downcase
        return true if host == "localhost" || host.end_with?(".localhost")

        ip = IPAddr.new(host)
        ip.loopback? || ip.private? || ip.link_local? || EXTRA_BLOCKED.any? { |range| range.include?(ip) }
      rescue IPAddr::InvalidAddressError
        false
      end

      def readable_text(body)
        ActionController::Base.helpers.strip_tags(body.to_s.byteslice(0, MAX_BYTES).to_s).squish.first(MAX_TEXT)
      end
    end
  end
end
