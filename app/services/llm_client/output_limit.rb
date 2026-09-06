class LlmClient
  module OutputLimit
    DEFAULT = 8_192

    def self.for(credential, model)
      advisory = credential.model_metadata(model)["max_output_tokens"]
      advisory.is_a?(Integer) && advisory.positive? ? [advisory, DEFAULT].min : DEFAULT
    end
  end
end
