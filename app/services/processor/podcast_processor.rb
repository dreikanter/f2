module Processor
  class PodcastProcessor < RssProcessor
    private

    # Feedjira parses itunes-namespaced feeds with ITunesRSSItem, which lacks
    # the enclosure collections patched onto RSSEntry, so the generic
    # sanitizer would drop the audio enclosure and cover art. Capture them
    # explicitly; episodes without their own artwork fall back to the
    # channel-level cover.
    def build_entries(feed_data)
      @channel_image = feed_data.try(:itunes_image).presence
      super
    end

    def sanitize_feedjira_entry(entry)
      super.merge(
        "itunes_image" => entry.try(:itunes_image).presence || @channel_image,
        "enclosure_url" => entry.try(:enclosure_url).presence
      )
    end
  end
end
