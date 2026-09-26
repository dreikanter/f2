module Processor
  # Validates AI response JSON before building entries for the feed pipeline.
  class LlmProcessor < Base
    class InvalidOutput < StandardError; end

    X_POST_HOSTS = %w[x.com www.x.com twitter.com www.twitter.com mobile.twitter.com].freeze
    X_SNOWFLAKE_EPOCH_MS = 1_288_834_974_657

    def process
      data = parse_output
      now = Time.current
      entries = data.fetch("items").map do |item|
        FeedEntry.new(
          feed: feed,
          uid: item["source_url"].nil? ? SecureRandom.uuid : Uid::Resolver.from_url(item["source_url"]),
          published_at: source_published_at(item) || now,
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

    def source_published_at(item)
      source_time = x_post_created_at(item["source_url"])
      claimed_time = parse_time(item["published_at"])
      return claimed_time unless source_time

      if source_time > Time.current || (claimed_time && (claimed_time - source_time).abs > 1.day)
        raise InvalidOutput, "AI source date conflicts with its X post permalink."
      end

      source_time
    end

    def x_post_created_at(url)
      uri = URI.parse(url.to_s)
      return unless X_POST_HOSTS.include?(uri.host&.downcase)

      post_id = uri.path.match(%r{\A/(?:[A-Za-z0-9_]{1,15}|i)/status/(\d+)(?:/.*)?\z})&.captures&.first
      return unless post_id && post_id.to_i.between?(1, (2**63) - 1)

      # X post IDs carry creation time, avoiding a model's guessed timezone.
      milliseconds = (post_id.to_i >> 22) + X_SNOWFLAKE_EPOCH_MS
      Time.at(Rational(milliseconds, 1_000)).utc
    rescue URI::InvalidURIError
      nil
    end

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
