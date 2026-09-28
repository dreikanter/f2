module Processor
  # Validates AI response JSON before building entries for the feed pipeline.
  class LlmProcessor < Base
    class InvalidOutput < StandardError; end

    def process
      data = parse_output
      entries = data.fetch("items").each_with_index.map do |item, index|
        FeedEntry.new(
          feed: feed,
          uid: item["source_url"].nil? ? raw_data.generated_uid(index) : Uid::Resolver.from_url(item["source_url"]),
          published_at: item["source_url"].nil? ? raw_data.started_at : parse_time(item["published_at"]),
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
