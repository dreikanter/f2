module Processor
  # Validates AI response JSON before building entries for the feed pipeline.
  class LlmProcessor < Base
    class InvalidOutput < StandardError; end

    def process
      data = parse_output
      now = Time.current
      entries = data.fetch("items").map do |item|
        FeedEntry.new(
          feed: feed,
          uid: item["source_url"].nil? ? SecureRandom.uuid : Uid::Resolver.from_url(item["source_url"]),
          published_at: parse_time(item["published_at"]) || now,
          status: :pending,
          raw_data: item
        )
      end
      Result.new(entries: entries, recognized: true)
    end

    private

    def parse_output
      data = JSON.parse(raw_data)
      unless JSONSchemer.schema(LlmOutput.new(feed).schema).valid?(data)
        raise InvalidOutput, "AI response does not match the output schema."
      end

      data
    rescue JSON::ParserError
      raise InvalidOutput, "AI response is not valid JSON.", cause: nil
    end
  end
end
