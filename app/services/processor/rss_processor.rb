module Processor
  class RssProcessor < Base
    def process
      parsed_feed = Feedjira.parse(raw_data)
      
      return [] unless parsed_feed&.entries

      parsed_feed.entries.map do |entry|
        FeedEntry.new(
          feed: feed,
          external_id: extract_external_id(entry),
          title: entry.title&.strip,
          content: entry.content || entry.summary,
          published_at: entry.published,
          source_url: entry.url,
          status: 0,
          raw_data: entry_to_hash(entry)
        )
      end
    rescue Feedjira::NoParserAvailable
      []
    end

    private

    def extract_external_id(entry)
      # Try to get a unique ID from the entry
      entry.id || entry.url || entry.title&.strip
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
