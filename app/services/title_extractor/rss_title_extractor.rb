module TitleExtractor
  # Extractor for RSS feed titles
  class RssTitleExtractor < Base
    # Extracts the feed title from RSS XML
    # @return [String, nil] the feed title or nil if it cannot be extracted
    def title
      return hostname_from_url if fetched_body.blank?

      doc = Nokogiri::XML(fetched_body)
      extract_title(doc).presence || hostname_from_url
    rescue Nokogiri::XML::SyntaxError
      hostname_from_url
    end

    private

    RSS1_NS = { "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#", "rss1" => "http://purl.org/rss/1.0/" }.freeze
    ATOM_NS = { "atom" => "http://www.w3.org/2005/Atom" }.freeze

    def extract_title(doc)
      rss_title = doc.at_xpath("//channel/title")&.text
      return rss_title.strip if rss_title.present?

      # RSS 1.0 (RDF): channel and title are in the http://purl.org/rss/1.0/ default namespace
      rdf_title = doc.at_xpath("//rdf:RDF/rss1:channel/rss1:title", RSS1_NS)&.text
      return rdf_title.strip if rdf_title.present?

      atom_title = doc.at_xpath("//atom:feed/atom:title", ATOM_NS)&.text
      atom_title&.strip
    end
  end
end
