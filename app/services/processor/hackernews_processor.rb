module Processor
  class HackernewsProcessor < Base
    MIN_SCORE = 300

    def process
      entries = Array(raw_data).filter_map do |item|
        next unless item.is_a?(Hash) && item["type"] == "story"
        next if item["deleted"] || item["dead"] || item["score"].to_i <= MIN_SCORE
        next unless item["id"].is_a?(Integer) && item["time"].is_a?(Integer)

        FeedEntry.new(feed: feed, uid: item.fetch("id").to_s,
                      published_at: Time.at(item.fetch("time")).utc, status: :pending, raw_data: item)
      end
      Result.new(entries: entries.sort_by(&:published_at).reverse, recognized: raw_data.is_a?(Array))
    end
  end
end
