# Extends Feedjira's RSS entry parser to collect enclosures and media elements
# as typed arrays rather than the built-in single-value :image attribute.
class FeedEnclosure
  include SAXMachine

  attribute :url
  attribute :type
  attribute :length
end

Feedjira::Parser::RSSEntry.class_eval do
  elements :enclosure,          as: :rss_enclosures,   class: FeedEnclosure
  elements :"media:content",    as: :media_contents,   class: FeedEnclosure
  elements :"media:thumbnail",  as: :media_thumbnails, class: FeedEnclosure
end
