module Processor
  class RssProcessor < Base
    def process
      parsed_feed = Feedjira.parse(raw_data)

      return [] unless parsed_feed&.entries

      parsed_feed.entries.map do |entry|
        FeedEntry.new(
          feed: feed,
          uid: extract_uid(entry),
          published_at: entry.published,
          status: :pending,
          raw_data: entry_to_hash(entry)
        )
      end
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
        link: entry.url,
        summary: entry.summary,
        content: entry.content,
        published: entry.published&.rfc3339,
        updated: entry.updated&.rfc3339,
        author: entry.author,
        categories: entry.categories,
        enclosures: entry.try(:enclosures) || []
      }
    end
  end
end
