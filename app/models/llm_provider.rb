# Code-only registry of AI providers `LlmClient` can talk to. Parallels
# `FeedProfile`. Drives the credential form generator (per-provider
# credential schema) and tells `LlmClient` which RubyLLM provider key
# to use.
class LlmProvider
  attr_reader :name, :display_name, :ruby_llm_provider, :credential_schema

  def initialize(name:, display_name:, ruby_llm_provider:, credential_schema:)
    @name = name
    @display_name = display_name
    @ruby_llm_provider = ruby_llm_provider
    @credential_schema = credential_schema
    freeze
  end

  def validate(client)
    client.health_check
  end

  PROVIDERS = {
    "anthropic" => new(
      name: "anthropic",
      display_name: "Anthropic (Claude)",
      ruby_llm_provider: :anthropic,
      credential_schema: {
        "type" => "object",
        "properties" => {
          "api_key" => { "type" => "string", "minLength" => 10, "title" => "API key" }
        },
        "required" => ["api_key"],
        "additionalProperties" => false
      }
    )
  }.freeze

  class << self
    def all
      PROVIDERS.values
    end

    def names
      PROVIDERS.keys
    end

    def find(name)
      return nil if name.nil?

      PROVIDERS[name.to_s]
    end

    def exists?(name)
      return false if name.nil?

      PROVIDERS.key?(name.to_s)
    end
  end
end
