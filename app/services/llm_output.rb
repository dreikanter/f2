# Structured response requested from the AI provider.
class LlmOutput
  DEFAULT_MAX_ITEMS = 3

  SCHEMA = {
    "type" => "object",
    "properties" => {
      "items" => {
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => {
            "body" => { "type" => "string" },
            "source_url" => { "type" => ["string", "null"] }
          },
          "required" => ["body", "source_url"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["items"],
    "additionalProperties" => false
  }.freeze

  def initialize(feed)
    @feed = feed
  end

  def max_items
    value = @feed.params["max_items"]
    schema = FeedProfile.parameter_schema_for("llm").fetch("properties").fetch("max_items")
    JSONSchemer.schema(schema).valid?(value) ? value : DEFAULT_MAX_ITEMS
  end

  def schema
    schema = SCHEMA.deep_dup
    schema.fetch("properties").fetch("items")["maxItems"] = max_items
    schema
  end
end
