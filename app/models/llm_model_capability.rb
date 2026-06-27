# Curated allowlist of (provider, model) pairs the system will run AI feeds
# on, annotated with the capabilities each pair satisfies. Code-only and
# reviewable, parallel to `LlmProvider` and `FeedProfile`.
#
# This is a deliberate gate, not auto-discovery. A model earns a place here
# only once it's known to deliver what an AI feed needs (structured output
# plus web access). Callers intersect this list with a credential's live
# `available_models` so a curated model the provider has since dropped falls
# out of the picker on its own.
#
# Entries describe model-level capability. Whether our adapter wires a given
# capability for a provider (e.g. Anthropic server tools via RubyLLM) is the
# adapter's concern, and entries are meant to be qualified empirically by a
# smoke probe before they land here rather than trusted from docs alone.
#
# `tier` records how reliably the pair honors structured output:
#   :native    — provider enforces the schema and hosts web access directly
#                (Anthropic). Most reliable.
#   :validated — schema and web access work, but enforcement is best-effort
#                (OpenRouter routes across upstreams); lean on response
#                healing plus JSONSchemer validation.
class LlmModelCapability
  STRUCTURED_OUTPUT = :structured_output
  WEB_SEARCH = :web_search
  WEB_FETCH = :web_fetch

  # The capabilities a model must satisfy to back an AI feed. Web fetch is a
  # bonus some models add; web search is the must-have for aggregation.
  REQUIRED_FOR_AI_FEED = [STRUCTURED_OUTPUT, WEB_SEARCH].freeze

  Entry = Data.define(:provider, :model, :capabilities, :tier)

  # Qualified starter set. OpenRouter currently carries the Anthropic family
  # only; more upstreams (OpenAI, Gemini) get added once the qualification
  # probe confirms web + schema together, not from capability flags alone.
  MODELS = [
    { provider: "anthropic", model: "claude-opus-4-8", capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH], tier: :native },
    { provider: "anthropic", model: "claude-opus-4-7", capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH], tier: :native },
    { provider: "anthropic", model: "claude-sonnet-4-6", capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH], tier: :native },
    { provider: "openrouter", model: "anthropic/claude-opus-4-8", capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH], tier: :validated },
    { provider: "openrouter", model: "anthropic/claude-sonnet-4-6", capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH], tier: :validated }
  ].map { |attrs| Entry.new(**attrs.merge(capabilities: attrs[:capabilities].freeze)) }.freeze

  INDEX = MODELS.index_by { |entry| [entry.provider, entry.model] }.freeze

  class << self
    def all
      MODELS
    end

    def find(provider, model)
      INDEX[[provider.to_s, model.to_s]]
    end

    def supported?(provider, model)
      INDEX.key?([provider.to_s, model.to_s])
    end

    # @return [Array<Symbol>] capabilities for the pair, or [] if unknown
    def capabilities_for(provider, model)
      find(provider, model)&.capabilities || []
    end

    def capable?(provider, model, capability)
      capabilities_for(provider, model).include?(capability)
    end

    # True when the pair satisfies every capability in `required`.
    def meets?(provider, model, required = REQUIRED_FOR_AI_FEED)
      capabilities = capabilities_for(provider, model)
      required.all? { |capability| capabilities.include?(capability) }
    end

    def qualified_for_ai_feed?(provider, model)
      meets?(provider, model)
    end

    def models_for(provider)
      MODELS.select { |entry| entry.provider == provider.to_s }
    end

    def qualified_models_for(provider)
      models_for(provider).select { |entry| qualified_for_ai_feed?(entry.provider, entry.model) }
    end

    def tier_for(provider, model)
      find(provider, model)&.tier
    end
  end
end
