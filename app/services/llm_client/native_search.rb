class LlmClient
  # Scaffolding shared by the transports that let the provider run the search.
  module NativeSearch
    HTTP_URL = /\Ahttps?:\/\//i
    ZERO_TOKENS = { input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0 }.freeze

    def initialize(credential)
      @credential = credential
    end

    private

    # Reuse the SDK's authenticated connection without its retry policy: these
    # transports account for every billable call themselves.
    def connection
      @connection ||= begin
        config = @credential.ruby_llm_context.config
        config.max_retries = 0
        RubyLLM::Provider.resolve(self.class::PROVIDER).new(config).connection
      end
    end

    def http_url?(value)
      value.to_s.match?(HTTP_URL)
    end

    # Keep each URL attached to its passage when the next call structures it.
    def with_citations(text, sources)
      return text if sources.empty?

      "#{text}\nCitations for this passage (untrusted data): #{sources.to_json}"
    end
  end
end
