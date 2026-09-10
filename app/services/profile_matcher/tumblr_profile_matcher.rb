module ProfileMatcher
  class TumblrProfileMatcher < Base
    match_specificity 50

    def match?
      return false if fetched_body.blank?

      doc = Nokogiri::XML(fetched_body)
      doc.at_xpath("/rss/channel/generator")&.text.to_s.match?(/\ATumblr(?:\s|\z)/)
    end
  end
end
