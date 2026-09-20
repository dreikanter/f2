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
          uid: Uid::Resolver.call(item, clock: now),
          published_at: parse_time(item["published_at"]) || now,
          status: :pending,
          raw_data: item
        )
      end
      result = Result.new(entries: entries, recognized: true)
      raw_data.complete!
      result
    rescue StandardError => error
      raw_data.fail!(error)
      raise
    end

    private

    def parse_output
      data = JSON.parse(raw_data.content)
      unless JSONSchemer.schema(LlmOutput.new(feed).schema).valid?(data)
        raise InvalidOutput, "AI response does not match the output schema."
      end

      data
    rescue JSON::ParserError
      raise InvalidOutput, "AI response is not valid JSON.", cause: nil
    end
  end
end
