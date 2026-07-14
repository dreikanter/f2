class LlmClient
  # Per-provider adjustments around the shared client-side web tools. RubyLLM
  # normalizes messages, schemas, tokens, and errors; adapters retain only the
  # request details and response cleanup that differ by provider.
  module Adapter
    REGISTRY = {
      "anthropic" => "Anthropic",
      "openrouter" => "OpenRouter",
      "moonshot" => "Moonshot"
    }.freeze

    def self.for(provider)
      const_get(REGISTRY.fetch(provider.to_s)).new
    end
  end
end
