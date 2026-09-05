class LlmClient
  module Tools
    # Client-side web search for providers without usable server-side web
    # access. Failed searches become error results the model can work around;
    # rejected credentials are deactivated to keep the failure visible.
    class WebSearch < RubyLLM::Tool
      description "Search the web. Returns result titles, URLs and snippets. " \
                  "Fetch a result URL with the web fetch tool to read the page."
      param :query, desc: "Search query", required: true

      MAX_RESULTS = 5

      def initialize(provider:, credential:, refresh_event: nil, budget: nil)
        super()
        @provider = provider
        @credential = credential
        @refresh_event = refresh_event
        @budget = budget
      end

      # Claimed before the argument is judged: a refused call still cost an LLM
      # round, and a model looping on bad arguments has to reach the halt too.
      def execute(query:)
        over_budget = @budget&.claim
        return over_budget if over_budget
        return { error: "Refused: query must not be blank." }.to_json if query.blank?

        return { error: "External search is unavailable. Continue with other available content." }.to_json if @unavailable

        record_usage
        results = @provider.search(query, max_results: MAX_RESULTS)
        { results: results.map(&:to_h) }.to_json
      rescue ::WebSearchProvider::AuthError => e
        Rails.error.report(e, context: { search_credential_id: @credential.id })
        @unavailable = true
        @credential.deactivate!(last_error: e.message)
        { error: "External search credentials were rejected. Continue with other available content." }.to_json
      rescue ::WebSearchProvider::Error => e
        Rails.error.report(e, context: { search_credential_id: @credential.id })
        { error: e.message }.to_json
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
