# frozen_string_literal: true

# Provider configuration and adapter factory. The UI reads provider metadata here;
# operations pass opaque credential data for each provider to interpret.
module LlmProvider
  PROVIDERS = {
    "openai" => {
      display_name: "OpenAI",
      adapter_class: Openai,
      validator_class: AiCredentialValidator::Openai
    }.freeze,
    "xai" => {
      display_name: "xAI",
      adapter_class: Xai,
      validator_class: AiCredentialValidator::Xai
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
      find(name).fetch(:adapter_class).new(credential_data: credential_data)
    end
  end
end
