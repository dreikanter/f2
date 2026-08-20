class LlmClient
  # Repairs two non-object roots models emit often enough to absorb rather
  # than fail: the whole payload JSON-encoded once more (a quoted string),
  # and the envelope dropped (a bare array where the schema wraps it in one
  # array property). Repaired output still goes through schema validation,
  # so a wrong guess fails there instead of leaking a malformed payload.
  # Shared with LlmCapabilityProbe so a model qualifies under exactly the
  # repairs production applies.
  module PayloadRepair
    module_function

    def repair(payload, output_schema)
      payload = unquote(payload) if payload.is_a?(String)
      return payload unless payload.is_a?(Array)

      key = envelope_key(output_schema)
      key ? { key => payload } : payload
    end

    def unquote(payload)
      JSON.parse(payload)
    rescue JSON::ParserError
      payload
    end

    # The array property a bare array can be re-wrapped under — only when the
    # schema's object root has exactly one, so the repair is unambiguous.
    def envelope_key(output_schema)
      return nil unless output_schema.is_a?(Hash) && output_schema["type"] == "object"

      array_keys = Hash(output_schema["properties"]).filter_map do |key, spec|
        key if spec.is_a?(Hash) && spec["type"] == "array"
      end
      array_keys.size == 1 ? array_keys.first : nil
    end
  end
end
