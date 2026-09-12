# Saved provider identities remain readable independently of their implementations.
class LlmProvider
  attr_reader :name, :display_name, :default_model, :implementation

  # @param name [String] saved provider key
  # @param display_name [String] provider label
  # @param default_model [String] suggested model ID
  # @param implementation [Object, nil] configured provider implementation
  def initialize(name:, display_name:, default_model:, implementation: nil)
    @name = name
    @display_name = display_name
    @default_model = default_model
    @implementation = implementation
    freeze
  end

  PROVIDERS = {
    "anthropic" => new(name: "anthropic", display_name: "Anthropic", default_model: "claude-sonnet-4-6"),
    "openrouter" => new(name: "openrouter", display_name: "OpenRouter", default_model: "anthropic/claude-sonnet-4-6"),
    "openai" => new(name: "openai", display_name: "OpenAI", default_model: "gpt-5.6-luna",
                    implementation: Ai::Providers::Openai.new.freeze),
    "moonshot" => new(name: "moonshot", display_name: "Moonshot (Kimi)", default_model: "kimi-k2.6")
  }.freeze

  class << self
    def all
      PROVIDERS.values
    end

    def available
      all.select(&:implementation)
    end

    def names
      PROVIDERS.keys
    end

    def find(name)
      PROVIDERS.fetch(name.to_s)
    end
  end
end
