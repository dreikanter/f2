module Processor
  class AerostatProcessor < RssProcessor
    private

    def sanitize_feedjira_entry(entry)
      itunes_image = entry.try(:itunes_image)
      enclosure_url = entry.try(:enclosure_url)

      if enclosure_url.blank?
        Rails.logger.warn(
          "[aerostat] feed=#{feed.id} uid=#{extract_uid(entry).inspect}: missing enclosure_url (no audio)"
        )
      end

      if itunes_image.blank?
        Rails.logger.warn(
          "[aerostat] feed=#{feed.id} uid=#{extract_uid(entry).inspect}: missing itunes_image (no cover art)"
        )
      end

      super.merge(
        "itunes_image" => itunes_image,
        "enclosure_url" => enclosure_url
      )
    end
  end
end
