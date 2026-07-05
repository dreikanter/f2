class LlmClient
  module Adapter
    # Moonshot (Kimi) via the OpenAI-compatible API. Two verified quirks drive
    # this adapter (plan-03): the server-side `$web_search` builtin never
    # engages through RubyLLM, so web access is a client-side fetch tool
    # instead; and structured output arrives markdown-fenced ~⅔ of the time,
    # so JSON is unwrapped before parsing.
    class Moonshot < Base
      FENCE = /\A```[a-z]*\n?(.*?)\n?```\z/m

      # Client-side retrieval: register the fetch tool so the model can pull
      # page content through RubyLLM's tool loop.
      def apply_web(chat, _model)
        chat.with_tool(LlmClient::Tools::WebFetch) if chat.respond_to?(:with_tool)
      end

      def unwrap_json(text)
        stripped = text.to_s.strip
        match = stripped.match(FENCE)
        match ? match[1].strip : stripped
      end
    end
  end
end
