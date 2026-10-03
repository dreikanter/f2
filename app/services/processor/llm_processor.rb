module Processor
  # Builds ordinary feed entries from the provider's structured response.
  class LlmProcessor < Base
    class InvalidOutput < StandardError; end

    def process
      data = parse_output
      now = Time.current
      entries = data.fetch("items").map do |item|
        FeedEntry.new(
          feed: feed,
          uid: item["source_url"].nil? ? SecureRandom.uuid : Uid::Resolver.from_url(item["source_url"], allow_homepage: true),
          published_at: parse_time(item["published_at"]) || now,
          status: :pending,
          raw_data: item
        )
      end
      Result.new(entries: entries, recognized: true)
    end

    private

    def parse_output
      JSON.parse(raw_data)
    rescue JSON::ParserError
      raise InvalidOutput, "AI response is not valid JSON.", cause: nil
    end
  end
end
