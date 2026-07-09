# Code-only registry of AI providers `LlmClient` can talk to. Parallels
# `FeedProfile`. Tells `LlmClient` which RubyLLM provider key to use.
# Every provider authenticates with a single API key; if one ever needs
# more fields, add them for that provider specifically rather than
# generalizing back to a schema.
#
# Provider-specific model names live here and nowhere above: `default_model`
# is what a feed uses when it carries no explicit override.
class LlmProvider
  attr_reader :name, :display_name, :ruby_llm_provider, :default_model, :api_base

  def initialize(name:, display_name:, ruby_llm_provider:, default_model:, api_base: nil, assume_model_exists: false)
    @name = name
    @display_name = display_name
    @ruby_llm_provider = ruby_llm_provider
    @default_model = default_model
    # OpenAI-compatible providers (Moonshot) reuse RubyLLM's :openai provider
    # pointed at their own base URL; native providers leave this nil.
    @api_base = api_base
    # True when the provider's models aren't in RubyLLM's bundled registry, so
    # a call must assert the model exists rather than look it up.
    @assume_model_exists = assume_model_exists
    freeze
  end

  def assume_model_exists?
    @assume_model_exists
  end

  # Applies this provider's credentials to a RubyLLM config. Keyed on the
  # RubyLLM provider (Moonshot authenticates as :openai with a custom base),
  # not the registry name.
  def configure(config, api_key)
    config.public_send("#{ruby_llm_provider}_api_key=", api_key)
    config.public_send("#{ruby_llm_provider}_api_base=", api_base) if api_base
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
    ),
    "moonshot" => new(
      name: "moonshot",
      display_name: "Moonshot (Kimi)",
      ruby_llm_provider: :openai,
      default_model: "kimi-k2.5",
      api_base: "https://api.moonshot.ai/v1",
      assume_model_exists: true
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
  end
end
