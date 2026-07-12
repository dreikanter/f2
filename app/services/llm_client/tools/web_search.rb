class LlmClient
  module Tools
    # Client-side web search for providers without usable server-side web
    # access. Backed by the WebSearch provider seam, so the vendor behind
    # the tool (Serper, Brave, Tavily) is a deployment choice.
    class WebSearch < RubyLLM::Tool
      description "Search the web. Returns result titles, URLs and snippets. " \
                  "Fetch a result URL with the web fetch tool to read the page."
      param :query, desc: "Search query", required: true

      MAX_RESULTS = 5

      def execute(query:)
        return { error: "Refused: query must not be blank." } if query.blank?
        return { error: "Web search is not configured." } unless ::WebSearch.configured?

        results = ::WebSearch.search(query, max_results: MAX_RESULTS)
        { results: results.map(&:to_h) }
      rescue ::WebSearch::Error => e
        { error: e.message }
      end
    end
  end
end
