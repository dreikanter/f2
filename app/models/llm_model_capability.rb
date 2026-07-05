# Dev-verified allowlist of (provider, model) pairs the AI engine may use, and
# the capability set each pair actually delivers through our stack (plan-03).
#
# Membership is qualification: a pair appears only once it's verified to work —
# there are no readiness tiers and no "experimental" rows. What the model picker
# offers for a feed is this matrix intersected with the credential's live model
# snapshot, so an unverified or web+schema-incapable model is never a silent,
# async footgun. A provider with no rows here (e.g. OpenRouter) simply isn't
# selectable for AI feeds.
#
# Capabilities:
#   :fetch      — read a known URL's content
#   :search     — discover content via web search
#   :structured — return native, strict-schema JSON
class LlmModelCapability
  CAPABILITIES = %i[fetch search structured].freeze

  # Verified live: Anthropic Sonnet/Opus do all three in one combined call
  # (#914); Kimi drives a client-side fetch tool and de-fenced JSON but its
  # server-side search doesn't engage through RubyLLM, so no :search (#917).
  ENTRIES = [
    { provider: "anthropic", model: "claude-sonnet-4-6", capabilities: %i[fetch search structured] },
    { provider: "anthropic", model: "claude-opus-4-7", capabilities: %i[fetch search structured] },
    { provider: "moonshot", model: "kimi-k2.5", capabilities: %i[fetch structured] }
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

    def capabilities_for(provider, model)
      find(provider, model)&.fetch(:capabilities) || []
    end
  end
end
