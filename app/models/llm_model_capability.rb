# Dev-verified allowlist of (provider, model) pairs the AI engine may use.
#
# Membership is qualification: a pair appears only once a capability probe run
# has shown it works through our stack, on the shape production actually calls
# (LlmCapabilityProbe). There are no readiness tiers and no "experimental" rows.
# What the model picker offers for a feed is this list intersected with the
# credential's live model snapshot, so an unverified model is never a silent,
# async footgun. A provider with no rows here (e.g. OpenRouter) simply isn't
# selectable for AI feeds.
#
# Rows carry no per-model capability flags. Every provider retrieves through our
# own client-side search and fetch tools (LlmClient::Adapter::Base#apply_web),
# so what a model's hosted retrieval can do never reaches a feed run — and the
# one thing that does vary, whether schema and tools survive the same call, is
# already a provider property the adapter carries (`combined_extraction?`).
#
# Verified on staging: Anthropic Sonnet drives the tools and returns
# strict-schema JSON in one combined call (#914). Kimi k2.6 drives the same
# tools under a system prompt but needs two-step extraction (#1186; it replaces
# the retired k2.5, qualified the same way).
class LlmModelCapability
  ENTRIES = [
    { provider: "anthropic", model: "claude-sonnet-4-6" },
    { provider: "moonshot", model: "kimi-k2.6" }
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
