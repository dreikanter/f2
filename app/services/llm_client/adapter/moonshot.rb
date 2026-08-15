class LlmClient
  module Adapter
    # Moonshot (Kimi) returns structured output in markdown fences often enough
    # that JSON must be unwrapped before parsing. The fence is matched wherever
    # it appears and whatever its tag's case, since a model that adds a sentence
    # of preamble or writes ```JSON is not a different failure.
    class Moonshot < Base
      FENCE = /```[a-z]*\n?(.*?)\n?```/mi

      def unwrap_json(text)
        stripped = text.to_s.strip
        match = stripped.match(FENCE)
        match ? match[1].strip : stripped
      end
    end
  end
end
