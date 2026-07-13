class LlmClient
  module Adapter
    # Moonshot (Kimi). Two verified quirks (plan-03): the `$web_search` builtin
    # never engages through RubyLLM, so web access is client-side tools —
    # search (when a WebSearch provider is configured) plus page fetch; and
    # structured output is markdown-fenced ~⅔ of the time, so its JSON is
    # unwrapped before parsing.
    class Moonshot < Base
      FENCE = /\A```[a-z]*\n?(.*?)\n?```\z/m

      def apply_web(chat, _model)
        if ::WebSearchProvider.configured?
          chat.with_tool(LlmClient::Tools::WebSearch.new(provider: ::WebSearchProvider.default))
        end
        chat.with_tool(LlmClient::Tools::WebFetch)
      end

      def unwrap_json(text)
        stripped = text.to_s.strip
        match = stripped.match(FENCE)
        match ? match[1].strip : stripped
      end
    end
  end
end
