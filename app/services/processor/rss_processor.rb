module Processor
  class RssProcessor < Base
    def process
      parsed_feed = Feedjira.parse(raw_data)

      return [] unless parsed_feed&.entries

      parsed_feed.entries.filter_map do |entry|
        uid = extract_uid(entry)
        next unless uid

        FeedEntry.new(
          feed: feed,
          uid: uid,
          published_at: entry.published,
          status: :pending,
          raw_data: entry_to_hash(entry)
        )
      end
    rescue Feedjira::NoParserAvailable
      []
    end

    private

    def extract_uid(entry)
      entry.id || entry.url
    end

    def entry_to_hash(entry)
      {
        id: entry.id,
        title: entry.title,
        url: entry.url,
        summary: entry.summary,
        content: entry.content,
        published: entry.published&.iso8601,
        updated: entry.updated&.iso8601,
        author: entry.author,
        categories: entry.categories
      }
    end
  end
end
