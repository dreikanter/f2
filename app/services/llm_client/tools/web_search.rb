class LlmClient
  module Tools
    # Client-side web search for providers without usable server-side web
    # access. Built around an injected, already-resolved WebSearchProvider,
    # so the vendor and API key are the caller's choice. Failures surface as
    # ordinary error results the model can read and work around — including
    # auth failures for now: letting one escape mid-run would bypass
    # LlmClient's one-usage-row-per-call accounting with nothing upstream to
    # catch it until credential-based resolution lands (spec 006 §5).
    class WebSearch < RubyLLM::Tool
      description "Search the web. Returns result titles, URLs and snippets. " \
                  "Fetch a result URL with the web fetch tool to read the page."
      param :query, desc: "Search query", required: true

      MAX_RESULTS = 5

      def initialize(provider:)
        super()
        @provider = provider
      end

      def execute(query:)
        return { error: "Refused: query must not be blank." } if query.blank?

        results = @provider.search(query, max_results: MAX_RESULTS)
        { results: results.map(&:to_h) }
      rescue ::WebSearchProvider::Error => e
        { error: e.message }
      end
    end
  end
end
