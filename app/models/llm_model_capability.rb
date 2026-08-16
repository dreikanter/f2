# Dev-verified allowlist of (provider, model) pairs the AI engine may use.
#
# Membership is qualification: a pair appears only once LlmCapabilityProbe has
# shown it works on the shape production calls. The model picker offers this
# list intersected with the credential's live snapshot, so an unverified model
# can't be selected and fail asynchronously mid-run. A provider with no rows
# isn't selectable for AI feeds at all.
#
# Rows are pairs and nothing else. Per-model capability flags would describe
# hosted retrieval, which never reaches a feed run — every provider retrieves
# through our own tools — and the one thing that does vary between models,
# whether schema and tools survive the same call, is an adapter property
# (`combined_extraction?`).
#
# Adding a pair: docs/llm-provider-qualification.md
class LlmModelCapability
  ENTRIES = [
    { provider: "anthropic", model: "claude-sonnet-4-6" },
    { provider: "moonshot", model: "kimi-k2.6" },
    { provider: "openai", model: "gpt-5.6-luna" }
  ].freeze

  class << self
    def all
      ENTRIES
    end

    def find(provider, model)
      ENTRIES.find { |entry| entry[:provider] == provider.to_s && entry[:model] == model.to_s }
    end

    def supported?(provider, model)
      !find(provider, model).nil?
    end

    # Verified model ids for a provider, in matrix order.
    def models_for(provider)
      ENTRIES.select { |entry| entry[:provider] == provider.to_s }.map { |entry| entry[:model] }
    end
  end
end
