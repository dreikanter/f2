class LlmClient
  module Adapter
    # Moonshot (Kimi) returns structured output in markdown fences often enough
    # that JSON must be unwrapped before parsing. Matched unanchored and
    # case-insensitively: preamble prose and a ```JSON tag are the same failure.
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
