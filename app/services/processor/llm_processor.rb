module Processor
  # Validates AI response JSON before building entries for the feed pipeline.
  class LlmProcessor < Base
    class InvalidOutput < StandardError; end

    def process
      data = JSON.parse(raw_data)
      unless JSONSchemer.schema(FeedProfile::UNIVERSAL_OUTPUT_SCHEMA).valid?(data)
        raise InvalidOutput, "AI response does not match the output schema."
      end

      now = Time.current
      entries = data.fetch("items").map do |item|
        FeedEntry.new(
          feed: feed,
          uid: Uid::Resolver.call(item, clock: now),
          published_at: parse_time(item["published_at"]) || now,
          status: :pending,
          raw_data: item
        )
      end
      Result.new(entries: entries, recognized: true)
    rescue JSON::ParserError
      raise InvalidOutput, "AI response is not valid JSON.", cause: nil
    end
  end
end
