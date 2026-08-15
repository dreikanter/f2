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
        candidates(text).find { |candidate| json?(candidate) } || text
      end

      # One candidate per bracket type, earliest opener first. Prose is
      # unrestricted, so a bracket can precede the payload ("Response [JSON]:
      # {...}") — parsing is the only thing that can tell a false opener from a
      # real one, and ordering by position keeps an array payload from being
      # read as the first object nested inside it.
      def candidates(text)
        OPENERS.filter_map do |opener, closer|
          first = text.index(opener)
          last = text.rindex(closer)
          next if first.nil? || last.nil? || last < first

          [first, text[first..last]]
        end.sort_by(&:first).map(&:last)
      end

      def json?(text)
        JSON.parse(text)
        true
      rescue JSON::ParserError
        false
      end
    end
  end
end
