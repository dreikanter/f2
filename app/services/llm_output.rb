# The response bound shared by AI instructions, provider schemas, and validation.
class LlmOutput
  DEFAULT_MAX_ITEMS = 10

  def initialize(feed)
    @feed = feed
  end

  def max_items
    @feed.params["max_items"].presence || DEFAULT_MAX_ITEMS
  end

  def schema
    schema = FeedProfile::UNIVERSAL_OUTPUT_SCHEMA.deep_dup
    schema.fetch("properties").fetch("items")["maxItems"] = max_items
    schema
  end
end
