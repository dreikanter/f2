# frozen_string_literal: true

# Provider configuration and client factory. The UI reads provider metadata here;
# operations build clients bound to individual credentials' API keys.
module LlmProvider
  PROVIDERS = {
    "openai" => {
      display_name: "OpenAI",
      default_model: "gpt-5.6-luna",
      client_class: Openai
    }.freeze
  }.freeze

  class << self
    def all
      PROVIDERS
    end

    def names
      PROVIDERS.keys
    end

    def find(name)
      PROVIDERS.fetch(name.to_s)
    end

    def build(name, api_key:)
      find(name).fetch(:client_class).new(api_key: api_key)
    end
  end
end
