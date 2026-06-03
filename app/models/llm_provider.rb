# Code-only registry of AI providers `LlmClient` can talk to. Parallels
# `FeedProfile`. Tells `LlmClient` which RubyLLM provider key to use.
# Every provider authenticates with a single API key; if one ever needs
# more fields, add them for that provider specifically rather than
# generalizing back to a schema.
class LlmProvider
  attr_reader :name, :display_name, :ruby_llm_provider

  def initialize(name:, display_name:, ruby_llm_provider:)
    @name = name
    @display_name = display_name
    @ruby_llm_provider = ruby_llm_provider
    freeze
  end

  PROVIDERS = {
    "anthropic" => new(
      name: "anthropic",
      display_name: "Anthropic",
      ruby_llm_provider: :anthropic
    ),
    "openrouter" => new(
      name: "openrouter",
      display_name: "OpenRouter",
      ruby_llm_provider: :openrouter
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
