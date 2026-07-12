class LlmClient
  module Tools
    # Client-side web search for providers without usable server-side web
    # access. Backed by WebSearchProvider, so the vendor behind the tool
    # (Serper, Brave, Tavily) is a deployment choice. An unconfigured
    # deployment surfaces as an ordinary error result the model can read.
    class WebSearch < RubyLLM::Tool
      description "Search the web. Returns result titles, URLs and snippets. " \
                  "Fetch a result URL with the web fetch tool to read the page."
      param :query, desc: "Search query", required: true

      MAX_RESULTS = 5

      def execute(query:)
        return { error: "Refused: query must not be blank." } if query.blank?

        results = ::WebSearchProvider.default.search(query, max_results: MAX_RESULTS)
        { results: results.map(&:to_h) }
      rescue ::WebSearchProvider::Error => e
        { error: e.message }
      end
    end
  end
end
