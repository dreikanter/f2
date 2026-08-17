class LlmClient
  module Adapter
    # Basic abstraction for an LLM provider adapter.
    class Base
      # Provider-specific request params that remain necessary alongside the
      # shared client-side web tools.
      def web_params(_model)
        {}
      end

      # Every provider uses the same credential-backed search and fetch tools.
      # Adapters may still add provider-specific request params, but search never
      # delegates to a provider-hosted implementation.
      #
      # Both tools share one budget so the pair can't outspend it between them.
      def apply_web(chat, model, search_provider:, search_credential:, refresh_event: nil)
        params = web_params(model)
        chat.with_params(**params) if params.present?
        budget = LlmClient::ToolBudget.new
        chat.with_tool(
          LlmClient::Tools::WebSearch.new(
            provider: search_provider,
            credential: search_credential,
            refresh_event: refresh_event,
            budget: budget
          )
        )
        chat.with_tool(LlmClient::Tools::WebFetch.new(budget: budget))
      end

      # True when one web+schema call returns grounded, schema-valid JSON; false
      # falls back to gather-then-structure (two calls).
      def combined_extraction?
        false
      end

      # RubyLLM's schema argument; the wrapper form is what carries strictness.
      def schema_payload(schema)
        { "schema" => schema, "strict" => schema_strict? }
      end

      # Constrained decoding where the provider's strict mode can express the
      # output schema. Off for providers whose strict mode cannot represent an
      # optional key, since they reject such a schema rather than relax it.
      def schema_strict?
        true
      end

      # Whether a failure means the key itself is finished — unfunded, overdue
      # or expired — rather than a fault that may clear. RubyLLM maps every 429
      # to a rate limit, but some vendors report a spent key that way, so
      # providers refine this.
      def dead_key?(_error)
        false
      end

      # Repairs structured-output text before JSON parsing. Default trusts clean
      # JSON; providers that wrap it (Moonshot fences) override.
      def unwrap_json(text)
        text
      end

      private

      # The vendor's own identifiers for a failure, read from the raw response
      # body a RubyLLM error carries. Vendors put the machine-readable name in
      # `type` or in `code` and not consistently the same one, so both are
      # returned rather than one being preferred.
      def error_codes(error)
        body = error.try(:response).try(:body)
        json = JSON.parse(body.to_s)
        reported = json.is_a?(Hash) ? json["error"] : nil
        return [] unless reported.is_a?(Hash)

        reported.values_at("type", "code").compact
      rescue JSON::ParserError
        []
      end
    end
  end
end
