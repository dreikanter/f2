module TitleExtractor
  # Extractor for RSS feed titles
  class RssTitleExtractor < Base
    # Extracts the feed title from RSS XML
    # @return [String, nil] the feed title or nil if it cannot be extracted
    def title
      return nil if fetched_body.blank?

      doc = Nokogiri::XML(fetched_body)
      extract_title(doc)
    rescue Nokogiri::XML::SyntaxError
      nil
    end

    private

    RDF_NS = { "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#" }.freeze
    ATOM_NS = { "atom" => "http://www.w3.org/2005/Atom" }.freeze

    def extract_title(doc)
      # Try RSS 2.0 format
      rss_title = doc.at_xpath("//channel/title")&.text
      return rss_title.strip if rss_title.present?

      # Try RSS 1.0 (RDF) format
      rdf_title = doc.at_xpath("//rdf:RDF/channel/title", RDF_NS)&.text
      return rdf_title.strip if rdf_title.present?

      # Try Atom format (e.g. YouTube)
      atom_title = doc.at_xpath("//atom:feed/atom:title", ATOM_NS)&.text
      atom_title&.strip
    end
  end
end
