class LlmClient
  module Tools
    # Client-side web search for providers without usable server-side web
    # access. Built around an injected, already-resolved WebSearchProvider,
    # so the vendor and API key are the caller's choice. Transient failures
    # surface as ordinary error results the model can read and work around;
    # an auth failure escapes instead — a dead key is a run-level problem
    # the model can't fix, and swallowing it would hide the failure forever.
    class WebSearch < RubyLLM::Tool
      description "Search the web. Returns result titles, URLs and snippets. " \
                  "Fetch a result URL with the web fetch tool to read the page."
      param :query, desc: "Search query", required: true

      MAX_RESULTS = 5

      def initialize(provider:, credential:, refresh_event: nil)
        super()
        @provider = provider
        @credential = credential
        @refresh_event = refresh_event
      end

      def execute(query:)
        return { error: "Refused: query must not be blank." } if query.blank?

        record_usage
        results = @provider.search(query, max_results: MAX_RESULTS)
        { results: results.map(&:to_h) }
      rescue ::WebSearchProvider::AuthError
        raise
      rescue ::WebSearchProvider::Error => e
        { error: e.message }
      end

      private

      # Best-effort: a failed accounting write must not take down the search —
      # or the whole run, since a non-search error escapes every rescue on the
      # way up and would abort the LLM call over a bookkeeping hiccup.
      def record_usage
        Rails.error.handle(StandardError, context: { search_credential_id: @credential.id }) do
          WebSearchUsage.record!(credential: @credential, refresh_event: @refresh_event)
        end
      end
    end
  end
end
