# Provider identities and defaults used by saved credentials and feed settings.
class LlmProvider
  attr_reader :name, :display_name, :ruby_llm_provider, :default_model, :api_base

  # @param name [String]
  # @param display_name [String]
  # @param ruby_llm_provider [Symbol]
  # @param default_model [String]
  # @param api_base [String, nil] set when the provider rides another's runtime
  #   at its own URL; native providers leave it nil
  # @param pin_system_role [Boolean] set when the provider rejects RubyLLM's
  #   default "developer" system role and needs "system"
  def initialize(name:, display_name:, ruby_llm_provider:, default_model:, api_base: nil, pin_system_role: false)
    @name = name
    @display_name = display_name
    @ruby_llm_provider = ruby_llm_provider
    @default_model = default_model
    @api_base = api_base
    @pin_system_role = pin_system_role
    freeze
  end

  def pin_system_role?
    @pin_system_role
  end

  # Applies this provider's credentials to a RubyLLM config. Keyed on the
  # RubyLLM provider (Moonshot authenticates as :openai with a custom base),
  # not the registry name.
  def configure(config, api_key)
    config.public_send("#{ruby_llm_provider}_api_key=", api_key)
    config.public_send("#{ruby_llm_provider}_api_base=", api_base) if api_base
    # RubyLLM's :openai provider sends system prompts as role "developer", which
    # OpenAI accepts but some OpenAI-compatible APIs reject with a 400.
    config.openai_use_system_role = true if pin_system_role?
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
    "openai" => new(
      name: "openai",
      display_name: "OpenAI",
      ruby_llm_provider: :openai,
      default_model: "gpt-5.6-luna"
    ),
    "moonshot" => new(
      name: "moonshot",
      display_name: "Moonshot (Kimi)",
      ruby_llm_provider: :openai,
      default_model: "kimi-k2.6",
      api_base: "https://api.moonshot.ai/v1",
      pin_system_role: true
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
