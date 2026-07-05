class LlmClient
  # Per-provider web-access params for the LLM request. RubyLLM normalizes the
  # rest of the request (messages, schema, tokens, errors) but has no web-access
  # abstraction, so each provider's raw params are merged into the request via
  # `with_params`. Selected by `credential.provider`.
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
