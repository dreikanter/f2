class LlmClient
  # Per-provider adjustments around the shared client-side web tools. RubyLLM
  # normalizes messages, schemas, tokens, and errors; adapters retain only the
  # request details and response cleanup that differ by provider.
  module Adapter
    REGISTRY = {
      "anthropic" => "Anthropic",
      "openrouter" => "OpenRouter",
      "openai" => "OpenAi",
      "moonshot" => "Moonshot"
    }.freeze

    def self.for(provider)
      const_get(REGISTRY.fetch(provider.to_s)).new
    end

    # The client-side tools are provider-independent. Search is optional; both
    # tools share one allowance.
    def self.web_tools(search_provider:, search_credential:, budget:, refresh_event: nil)
      tools = []
      tools << Tools::WebSearch.new(provider: search_provider, credential: search_credential,
                                    refresh_event: refresh_event, budget: budget) if search_provider
      tools << Tools::WebFetch.new(budget: budget)
    end
  end
end
