module TitleExtractor
  # Extractor for RSS feed titles
  class RssTitleExtractor < Base
    # Extracts the feed title from RSS XML
    # @return [String, nil] the feed title or nil if it cannot be extracted
    def title
      return nil if response.body.blank?

      doc = Nokogiri::XML(response.body)
      extract_title(doc)
    rescue Nokogiri::XML::SyntaxError
      nil
    end

    private

    def extract_title(doc)
      # Try RSS 2.0 format
      rss_title = doc.at_xpath("//channel/title")&.text
      return rss_title.strip if rss_title.present?

      # Try RSS 1.0 (RDF) format
      rdf_title = doc.at_xpath("//rdf:RDF/channel/title")&.text
      rdf_title&.strip
    end
  end
end
