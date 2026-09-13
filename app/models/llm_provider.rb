# frozen_string_literal: true

# Provider configuration and client factory. The UI reads provider metadata here;
# operations pass opaque credential data for each provider to interpret.
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

    def build(name, credential_data:)
      find(name).fetch(:client_class).new(credential_data: credential_data)
    end
  end
end
