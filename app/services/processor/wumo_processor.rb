module Processor
  class WumoProcessor < RssProcessor
    private

    # Wumo omits pubDate. Resolve it before the refresh workflow applies the
    # import threshold, or the whole RSS window would look newly published.
    def build_entries(feed_data)
      super.each do |entry|
        entry.published_at ||= date_from_url(entry.raw_data["link"])
      end
    end

    def date_from_url(url)
      date = URI.parse(url.to_s).path.to_s.match(%r{\A/wumo/(\d{4}/\d{2}/\d{2})/?\z})
      Date.iso8601(date[1].tr("/", "-")).to_time(:utc) if date
    rescue URI::InvalidURIError, Date::Error
      nil
    end
  end
end
