class LlmClient
  module Tools
    # Client-side retrieval for providers without usable server-side web access
    # (Moonshot/Kimi). The model supplies the URL, so it is validated as a
    # public http(s) URL (PublicUrl, spec 005 §8) before any request.
    class WebFetch < RubyLLM::Tool
      description "Fetch the readable text of a public web page. Pass one absolute http(s) URL."
      param :url, desc: "Absolute http(s) URL of the page to fetch", required: true

      MAX_REDIRECTS = 3
      MAX_BYTES = 200_000
      MAX_TEXT = 8_000

      def initialize(budget: nil)
        super()
        @budget = budget
      end

      # Claimed before the URL is judged: a refused call still cost an LLM
      # round, and a model looping on bad URLs has to reach the halt too.
      def execute(url:)
        over_budget = @budget&.claim
        return over_budget if over_budget
        return { error: "Refused: pass one absolute public http(s) URL." }.to_json unless PublicUrl.safe?(url)

        # public-only so a redirect can't slip past the check above to an
        # internal address (SSRF; spec 005 §8).
        response = HttpClient.build(max_redirects: MAX_REDIRECTS)
                             .get(url.to_s.strip, options: { validate_url: PublicUrl.method(:safe?) })
        return { error: "HTTP #{response.status}" }.to_json unless response.success?

        { content: readable_text(response.body) }.to_json
      rescue HttpClient::Error => e
        { error: e.message }.to_json
      end

      private

      def readable_text(body)
        ActionController::Base.helpers.strip_tags(body.to_s.byteslice(0, MAX_BYTES).to_s).squish.first(MAX_TEXT)
      end
    end
  end
end
