class LlmClient
  module Adapter
    # OpenAI needs neither the request tweaks nor the response repair the other
    # providers do: structured outputs come back as clean JSON, and the shared
    # client-side web tools need no extra params. Whether a schema and tools
    # survive the same call is what the capability probe decides, so this stays
    # on Base's two-call fallback until a run says otherwise.
    class OpenAi < Base
      # gpt-5.6 reasons by default, and OpenAI rejects function tools alongside
      # reasoning on /v1/chat/completions — the endpoint RubyLLM speaks — with
      # a 400 naming this opt-out. Scoped to tool-enabled calls, so the
      # structure step keeps the model's reasoning.
      def web_params(_model)
        { reasoning_effort: "none" }
      end

      # OpenAI's strict mode requires every key in `properties` to appear in
      # `required`, recursively. FeedProfile::UNIVERSAL_OUTPUT_SCHEMA marks
      # only `body` and `source_url` required, so a strict call is rejected
      # outright; unconstrained, the schema still shapes the response and the
      # normalizer still validates what comes back.
      def schema_strict?
        false
      end
    end
  end
end
