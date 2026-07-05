require "ipaddr"

class LlmClient
  module Tools
    # Client-side retrieval tool handed to models whose provider has no usable
    # server-side web access (Moonshot/Kimi). The model calls it with a URL;
    # we fetch the page ourselves and return its readable text.
    #
    # The URL is model-controlled, so it is a server-side request forgery
    # surface (spec 005 §8): only absolute public http(s) URLs are fetched —
    # non-http schemes, credentials, localhost, and private/link-local ranges
    # are refused before any request leaves the app.
    class WebFetch < RubyLLM::Tool
      description "Fetch the readable text of a public web page. Pass one absolute http(s) URL."
      param :url, desc: "Absolute http(s) URL of the page to fetch", required: true

      MAX_REDIRECTS = 3
      MAX_BYTES = 200_000
      MAX_TEXT = 8_000
      PRIVATE_V4 = [
        IPAddr.new("127.0.0.0/8"), IPAddr.new("10.0.0.0/8"), IPAddr.new("172.16.0.0/12"),
        IPAddr.new("192.168.0.0/16"), IPAddr.new("169.254.0.0/16"), IPAddr.new("0.0.0.0/8")
      ].freeze

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
        return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
        return if private_host?(uri.host)

        uri
      rescue URI::InvalidURIError
        nil
      end

      def private_host?(host)
        host = host.downcase
        return true if host == "localhost" || host.end_with?(".localhost")

        ip = IPAddr.new(host)
        ip.loopback? || ip.private? || ip.link_local? || PRIVATE_V4.any? { |range| range.include?(ip) }
      rescue IPAddr::InvalidAddressError
        false # a hostname, not an IP literal — allowed
      end

      def readable_text(body)
        ActionController::Base.helpers.strip_tags(body.to_s.byteslice(0, MAX_BYTES).to_s).squish.first(MAX_TEXT)
      end
    end
  end
end
