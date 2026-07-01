# Curated allowlist of (provider, model) pairs the system will run AI feeds
# on. Code-only and reviewable, parallel to `LlmProvider` and `FeedProfile`.
#
# Every AI feed needs the same full feature set — structured output, web
# search, and web fetch — so membership *is* qualification: a pair earns a
# place here only once it's known to deliver all three. A model that can't do
# the full set simply isn't listed.
#
# Callers intersect this list with a credential's live `available_models`, so a
# curated model the provider has since dropped falls out of the picker on its
# own. How the adapter wires each provider (Anthropic server tools vs
# OpenRouter web server tools) is the adapter's concern, and entries are meant
# to be qualified empirically by a smoke probe before they land here.
class LlmModelCapability
  Entry = Data.define(:provider, :model)

  # OpenRouter web search and web fetch come from OpenRouter's web server tools
  # (available across its catalog), so OpenRouter models clear the web bar
  # regardless of the underlying model's native tools. Slugs flagged below are
  # cheap staging candidates to confirm against the live catalog (Kimi in
  # particular is known to flip to plain text instead of honoring
  # tools/response_format).
  MODELS = [
    { provider: "anthropic", model: "claude-opus-4-8" },
    { provider: "anthropic", model: "claude-opus-4-7" },
    { provider: "anthropic", model: "claude-sonnet-4-6" },
    { provider: "openrouter", model: "anthropic/claude-opus-4-8" },
    { provider: "openrouter", model: "anthropic/claude-sonnet-4-6" },
    { provider: "openrouter", model: "anthropic/claude-haiku-4-5" },
    { provider: "openrouter", model: "google/gemini-2.5-flash" }, # verify slug
    { provider: "openrouter", model: "openai/gpt-4o-mini" }, # verify slug
    { provider: "openrouter", model: "moonshotai/kimi-k2" } # flaky; staging only
  ].map { |attrs| Entry.new(**attrs) }.freeze

  INDEX = MODELS.index_by { |entry| [entry.provider, entry.model] }.freeze

  class << self
    def all
      MODELS
    end

    def find(provider, model)
      INDEX[[provider.to_s, model.to_s]]
    end

    # Membership is qualification: every listed pair supports the full AI-feed
    # feature set, so this is the gate for backing an AI feed.
    def supported?(provider, model)
      INDEX.key?([provider.to_s, model.to_s])
    end

    def models_for(provider)
      MODELS.select { |entry| entry.provider == provider.to_s }
    end
  end
end
