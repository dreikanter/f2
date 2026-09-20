# The response bound shared by AI instructions, provider schemas, and validation.
class LlmOutput
  DEFAULT_MAX_ITEMS = 10

  def initialize(feed)
    @feed = feed
  end

  def max_items
    value = @feed.params["max_items"]
    schema = FeedProfile.parameter_schema_for("llm").fetch("properties").fetch("max_items")
    JSONSchemer.schema(schema).valid?(value) ? value : DEFAULT_MAX_ITEMS
  end

  def schema
    schema = FeedProfile::UNIVERSAL_OUTPUT_SCHEMA.deep_dup
    schema.fetch("properties").fetch("items")["maxItems"] = max_items
    schema
  end
end
