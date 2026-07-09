module Processor
  # Wraps loader-emitted structured items as FeedEntry instances without
  # any further parsing. Used by AI-extraction profiles where the loader
  # already produced the universal post shape.
  class PassthroughProcessor < Base
    def process
      items = Array(raw_data)
      entries = items.filter_map do |item|
        next unless item.is_a?(Hash)

        item = item.deep_stringify_keys
        FeedEntry.new(
          feed: feed,
          # A digest item (source_url: null) gets a period uid; a feed-style
          # permalink a normalized uid; an unusable permalink resolves to nil and
          # is dropped-and-counted by the workflow (spec §3), so we no longer
          # swallow it here.
          uid: Uid::Resolver.call(item, clock: Time.current),
          # AI-extracted items rarely come with a reliable published_at;
          # fall back to the current time so downstream invariants hold.
          published_at: parse_time(item["published_at"]) || Time.current,
          status: :pending,
          raw_data: item
        )
      end
      Result.new(entries: entries, recognized: true)
    end

    private

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
