class LlmClient
  module Adapter
    # Moonshot (Kimi) returns structured output in markdown fences often enough
    # that JSON must be unwrapped before parsing.
    class Moonshot < Base
      FENCE = /\A```[a-z]*\n?(.*?)\n?```\z/m

      def unwrap_json(text)
        stripped = text.to_s.strip
        match = stripped.match(FENCE)
        match ? match[1].strip : stripped
      end
    end
  end
end
