module Processor
  class AerostatProcessor < RssProcessor
    private

    def sanitize_feedjira_entry(entry)
      super.merge(
        "itunes_image" => entry.try(:itunes_image),
        "enclosure_url" => entry.try(:enclosure_url)
      )
    end
  end
end
