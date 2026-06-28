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
class LlmModelCapability
  STRUCTURED_OUTPUT = :structured_output
  WEB_SEARCH = :web_search
  WEB_FETCH = :web_fetch

  # The capabilities a model must satisfy to back an AI feed. Web fetch is a
  # bonus some models add; web search is the must-have for aggregation.
  REQUIRED_FOR_AI_FEED = [STRUCTURED_OUTPUT, WEB_SEARCH].freeze

  # `tier` records how reliably the pair honors structured output and how far
  # to trust it:
  #   :native       — provider enforces the schema directly (Anthropic). Most
  #                   reliable.
  #   :validated    — schema and web access work, but enforcement is best-effort
  #                   (OpenRouter routes across upstreams); lean on response
  #                   healing plus JSONSchemer validation.
  #   :experimental — staging test candidate whose slug and/or schema fidelity
  #                   still needs confirmation. With no production yet, the
  #                   matrix doubles as the staging test bench, so candidates
  #                   may land ahead of a qualifying probe.
  TIERS = %i[native validated experimental].freeze

  Entry = Data.define(:provider, :model, :capabilities, :tier)

  # Curated set. Anthropic Opus 4.8/4.7 and Sonnet 4.6 carry native structured
  # output plus dynamic-filtering web search and web fetch. Haiku 4.5 is the
  # cheap Anthropic option but only has basic web search (no dynamic filtering)
  # and its web fetch is unconfirmed.
  #
  # OpenRouter entries get web search and web fetch (full page content from any
  # URL) from OpenRouter's web server tools, available across its catalog;
  # schema enforcement is best-effort. `:experimental` slugs are cheap staging
  # test candidates to confirm against the live catalog (Kimi in particular is
  # known to flip to plain text instead of honoring tools/response_format). The
  # live intersection with a credential's available_models prunes any slug that
  # doesn't actually exist for that credential.
  MODELS = [
    {
      provider: "anthropic",
      model: "claude-opus-4-8",
      capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH],
      tier: :native
    },
    {
      provider: "anthropic",
      model: "claude-opus-4-7",
      capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH],
      tier: :native
    },
    {
      provider: "anthropic",
      model: "claude-sonnet-4-6",
      capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH],
      tier: :native
    },
    {
      provider: "anthropic",
      model: "claude-haiku-4-5",
      capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH], # basic web search only; native web fetch unconfirmed
      tier: :native
    },
    {
      provider: "openrouter",
      model: "anthropic/claude-opus-4-8",
      capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH],
      tier: :validated
    },
    {
      provider: "openrouter",
      model: "anthropic/claude-sonnet-4-6",
      capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH],
      tier: :validated
    },
    {
      provider: "openrouter",
      model: "anthropic/claude-haiku-4-5",
      capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH],
      tier: :validated
    },
    {
      provider: "openrouter",
      model: "google/gemini-2.5-flash", # verify slug
      capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH],
      tier: :experimental
    },
    {
      provider: "openrouter",
      model: "openai/gpt-4o-mini", # verify slug
      capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH],
      tier: :experimental
    },
    {
      provider: "openrouter",
      model: "moonshotai/kimi-k2", # flaky; staging only
      capabilities: [STRUCTURED_OUTPUT, WEB_SEARCH, WEB_FETCH],
      tier: :experimental
    }
  ].map { |attrs| Entry.new(**attrs.merge(capabilities: attrs[:capabilities].freeze)) }.freeze

  INDEX = MODELS.index_by { |entry| [entry.provider, entry.model] }.freeze

  class << self
    def all
      MODELS
    end

    def find(provider, model)
      INDEX[[provider.to_s, model.to_s]]
    end

    # @return [Array<Symbol>] capabilities for the pair, or [] if unknown
    def capabilities_for(provider, model)
      find(provider, model)&.capabilities || []
    end

    def tier_for(provider, model)
      find(provider, model)&.tier
    end

    # True when the pair carries every capability an AI feed requires.
    def qualified_for_ai_feed?(provider, model)
      capabilities = capabilities_for(provider, model)
      REQUIRED_FOR_AI_FEED.all? { |capability| capabilities.include?(capability) }
    end

    def qualified_models_for(provider)
      MODELS.select { |entry| entry.provider == provider.to_s && qualified_for_ai_feed?(entry.provider, entry.model) }
    end
  end
end
