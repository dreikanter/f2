class LlmClient
  module Adapter
    # Moonshot (Kimi) returns structured output in markdown fences often enough
    # that JSON must be unwrapped before parsing.
    class Moonshot < Base
      # Unanchored and case-insensitive, so preamble prose and a ```JSON tag are
      # both absorbed. Greedy on purpose: the payload itself may quote a fenced
      # code block, and the closing fence is the last one, not the first.
      FENCE = /```[a-z]*\n?(.*)\n?```/mi

      OPENERS = { "{" => "}", "[" => "]" }.freeze

      def unwrap_json(text)
        stripped = text.to_s.strip
        # Already-clean JSON is returned untouched — a fence quoted inside a
        # string value is content, not a wrapper.
        return stripped if stripped.start_with?(*OPENERS.keys)

        match = stripped.match(FENCE)
        return match[1].strip if match

        outermost_json(stripped)
      end

      private

      # Preamble with no fence at all ("Here is the JSON: {...}"). Reached only
      # when nothing fenced matched, so it can't disturb the fenced path. Text
      # holding no JSON at all is returned as-is, to fail as the parse error it
      # is rather than as a silent truncation.
      def outermost_json(text)
        opener = text.index(/[{\[]/)
        return text if opener.nil?

        closer = text.rindex(OPENERS.fetch(text[opener]))
        return text if closer.nil? || closer < opener

        text[opener..closer]
      end
    end
  end
end
