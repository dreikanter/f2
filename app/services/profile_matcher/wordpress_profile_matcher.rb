module ProfileMatcher
  class WordpressProfileMatcher < Base
    match_specificity 50

    def match?
      return false if fetched_body.blank?

      doc = Nokogiri::XML(fetched_body)
      generator = doc.at_xpath("/rss/channel/generator | /atom:feed/atom:generator", "atom" => "http://www.w3.org/2005/Atom")
      return false unless generator

      url = generator["uri"].presence || generator.text
      URI.parse(url).host == "wordpress.org"
    rescue URI::InvalidURIError
      false
    end
  end
end
