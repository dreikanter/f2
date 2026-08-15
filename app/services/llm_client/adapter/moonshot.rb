class LlmClient
  module Adapter
    # Moonshot (Kimi) returns structured output in markdown fences often enough
    # that JSON must be unwrapped before parsing.
    class Moonshot < Base
      # Unanchored and case-insensitive, so preamble prose and a ```JSON tag are
      # both absorbed. Greedy on purpose: the payload itself may quote a fenced
      # code block, and the closing fence is the last one, not the first.
      FENCE = /```[a-z]*\n?(.*)\n?```/mi

      def unwrap_json(text)
        stripped = text.to_s.strip
        # Already-clean JSON is returned untouched — a fence quoted inside a
        # string value is content, not a wrapper.
        return stripped if stripped.start_with?("{", "[")

        match = stripped.match(FENCE)
        match ? match[1].strip : stripped
      end
    end
  end
end
