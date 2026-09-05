class LlmClient
  module Adapter
    # Moonshot (Kimi) returns structured output in markdown fences often enough
    # that JSON must be unwrapped before parsing.
    class Moonshot < Base
      def native_search_transport
        MoonshotSearch
      end

      def unsupported_schema?(error)
        OpenAi.new.unsupported_schema?(error)
      end

      # Unanchored and case-insensitive, so preamble prose and a ```JSON tag are
      # both absorbed. Greedy on purpose: the payload itself may quote a fenced
      # code block, and the closing fence is the last one, not the first.
      FENCE = /```[a-z]*\n?(.*)\n?```/mi

      OPENERS = { "{" => "}", "[" => "]" }.freeze

      # Moonshot reports an unfunded, overdue or expired account as a 429, the
      # same status it uses for throttling and for an overloaded engine.
      SPENT_KEY_CODES = %w[exceeded_current_quota_error].freeze

      def dead_key?(error)
        error_codes(error).intersect?(SPENT_KEY_CODES)
      end

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

      # Preamble with no fence at all ("Here is the JSON: {...}"). Text holding
      # no JSON is returned intact, so it fails as the parse error it is rather
      # than as a mangled slice.
      def outermost_json(text)
        candidates(text).find { |candidate| json?(candidate) } || text
      end

      # Prose is unrestricted, so a bracket can precede the payload ("Response
      # [JSON]: {...}") — only a parse tells a false opener from a real one.
      # Earliest opener first, so an array payload is not read as the first
      # object nested inside it.
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
