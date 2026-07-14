class LlmClient
  module Tools
    # Client-side web search for providers without usable server-side web
    # access. Built around an injected, already-resolved WebSearchProvider,
    # so the vendor and API key are the caller's choice. Transient failures
    # surface as ordinary error results the model can read and work around;
    # an auth failure escapes instead — a dead key is a run-level problem
    # the model can't fix, and swallowing it would hide the failure forever.
    #
    # Each provider call is billed, so each one records a usage event on the
    # credential (spec 006 §6). Recording is best-effort: accounting must
    # never break a search that already succeeded.
    class WebSearch < RubyLLM::Tool
      description "Search the web. Returns result titles, URLs and snippets. " \
                  "Fetch a result URL with the web fetch tool to read the page."
      param :query, desc: "Search query", required: true

      MAX_RESULTS = 5

      def initialize(provider:, credential: nil, feed: nil, purpose: :scheduled_run)
        super()
        @provider = provider
        @credential = credential
        @feed = feed
        @purpose = purpose
      end

      def execute(query:)
        return { error: "Refused: query must not be blank." } if query.blank?

        results = @provider.search(query, max_results: MAX_RESULTS)
        record_call(outcome: :success)
        { results: results.map(&:to_h) }
      rescue ::WebSearchProvider::AuthError => e
        record_call(outcome: :error, error: e.message)
        raise
      rescue ::WebSearchProvider::Error => e
        record_call(outcome: :error, error: e.message)
        { error: e.message }
      end

      private

      def record_call(outcome:, error: nil)
        return if @credential.nil?

        Rails.error.handle(StandardError, context: { search_credential_id: @credential.id }) do
          @credential.record_search_call(purpose: @purpose, outcome: outcome, feed: @feed, error: error)
        end
      end
    end
  end
end
