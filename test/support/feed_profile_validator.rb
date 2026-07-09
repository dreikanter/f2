# Test-only helper: validates entries from FeedProfile::PROFILES against
# the registry contract (specs/001-smart-feed-creation/contracts/profile_registry.md).
# Lives under test/support because nothing in production needs it — the
# constant is frozen at load time, so we only need to assert its shape during CI.
module FeedProfileValidator
  Error = Class.new(StandardError)

  ENTRY_SCHEMA = {
    "type" => "object",
    "additionalProperties" => false,
    "required" => %w[
      display_name
      description
      input_shape
      depends_on_ai
      parameter_schema
      loader
      processor
      normalizer
    ],
    "properties" => {
      "display_name" => { "type" => "string", "minLength" => 1, "maxLength" => 80 },
      "description" => { "type" => "string", "minLength" => 1, "maxLength" => 200 },
      "input_shape" => { "type" => "string", "enum" => %w[url query any] },
      "depends_on_ai" => { "type" => "boolean" },
      "matcher" => { "type" => "string", "minLength" => 1 },
      "parameter_schema" => { "type" => "object" },
      "loader" => { "$ref" => "#/$defs/stage_entry" },
      "processor" => { "$ref" => "#/$defs/stage_entry" },
      "normalizer" => { "$ref" => "#/$defs/stage_entry" },
      "title_extractor" => { "type" => %w[string null] }
    },
    "$defs" => {
      "stage_entry" => {
        "type" => "object",
        "required" => %w[class config],
        "properties" => {
          "class" => { "type" => "string", "minLength" => 1 },
          "config" => { "type" => "object" }
        },
        "additionalProperties" => false
      }
    }
  }.freeze

  def self.validate!(profiles = FeedProfile::PROFILES)
    schemer = JSONSchemer.schema(ENTRY_SCHEMA)
    failures = []

    profiles.each do |key, entry|
      stringified = deep_stringify_symbols(entry)
      schemer.validate(stringified).each do |err|
        pointer = err["data_pointer"].to_s
        failures << "FeedProfile #{key.inspect}#{pointer}: #{err['error']}"
      end

      if entry[:depends_on_ai] && !entry.dig(:loader, :config, :output_schema).is_a?(Hash)
        failures << "FeedProfile #{key.inspect}: loader.config.output_schema is required when depends_on_ai is true"
      end

      # The AI profile registers no matcher (structural detection exclusion,
      # spec §7); every deterministic profile must declare one.
      if !entry[:depends_on_ai] && entry[:matcher].to_s.empty?
        failures << "FeedProfile #{key.inspect}: matcher is required for non-AI profiles"
      end
    end

    return if failures.empty?

    raise Error, "Invalid FeedProfile registry:\n  - " + failures.join("\n  - ")
  end

  def self.deep_stringify_symbols(value)
    case value
    when Hash
      value.each_with_object({}) do |(k, v), acc|
        acc[k.is_a?(Symbol) ? k.to_s : k] = deep_stringify_symbols(v)
      end
    when Array
      value.map { |v| deep_stringify_symbols(v) }
    when Symbol
      value.to_s
    else
      value
    end
  end
end
