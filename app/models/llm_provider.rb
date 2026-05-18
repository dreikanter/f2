# Code-only registry of AI providers `LlmClient` can talk to. Parallels
# `FeedProfile`. Drives the credential form generator (per-provider
# credential schema) and tells `LlmClient` which RubyLLM provider key
# to use.
module LlmProvider
  PROVIDERS = {
    "anthropic" => {
      display_name: "Anthropic (Claude)",
      ruby_llm_provider: :anthropic,
      credential_schema: {
        "type" => "object",
        "properties" => {
          "api_key" => { "type" => "string", "minLength" => 10 }
        },
        "required" => ["api_key"],
        "additionalProperties" => false
      },
      validate_call: ->(client) { client.health_check }
    }
  }.freeze

  class << self
    def all
      PROVIDERS.keys
    end

    def exists?(provider)
      PROVIDERS.key?(provider.to_s)
    end

    def [](provider)
      PROVIDERS[provider.to_s]
    end

    def display_name_for(provider)
      PROVIDERS.dig(provider.to_s, :display_name)
    end

    def credential_schema_for(provider)
      PROVIDERS.dig(provider.to_s, :credential_schema)
    end

    def ruby_llm_provider_for(provider)
      PROVIDERS.dig(provider.to_s, :ruby_llm_provider)
    end
  end
end
