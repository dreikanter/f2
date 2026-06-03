module Processor
  class YoutubeProcessor < RssProcessor
    private

    def sanitize_feedjira_entry(entry)
      super.merge("thumbnail" => entry.try(:media_thumbnail_url))
    end
  end
end
