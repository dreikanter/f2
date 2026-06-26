# Code-only registry of AI providers `LlmClient` can talk to. Parallels
# `FeedProfile`. Tells `LlmClient` which RubyLLM provider key to use.
# Every provider authenticates with a single API key; if one ever needs
# more fields, add them for that provider specifically rather than
# generalizing back to a schema.
#
# `default_model` is the model a feed falls back to when it carries no
# explicit override. Provider-specific model names live here and nowhere
# above this layer, so deprecating a model means editing one line.
class LlmProvider
  attr_reader :name, :display_name, :ruby_llm_provider, :default_model

  def initialize(name:, display_name:, ruby_llm_provider:, default_model:)
    @name = name
    @display_name = display_name
    @ruby_llm_provider = ruby_llm_provider
    @default_model = default_model
    freeze
  end

  PROVIDERS = {
    "anthropic" => new(
      name: "anthropic",
      display_name: "Anthropic",
      ruby_llm_provider: :anthropic,
      default_model: "claude-sonnet-4-6"
    ),
    "openrouter" => new(
      name: "openrouter",
      display_name: "OpenRouter",
      ruby_llm_provider: :openrouter,
      default_model: "anthropic/claude-sonnet-4-6"
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
      PROVIDERS.fetch(name.to_s)
    end

    def exists?(name)
      return false if name.nil?

      PROVIDERS.key?(name.to_s)
    end
  end
end
