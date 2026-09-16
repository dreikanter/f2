# frozen_string_literal: true

# Provider configuration and client factory. The UI reads provider metadata here;
# operations pass opaque credential data for each provider to interpret.
module LlmProvider
  PROVIDERS = {
    "openai" => {
      display_name: "OpenAI",
      default_model: "gpt-5.6-luna",
      client_class: Openai,
      validator_class: AiCredentialValidator::Openai
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

    # Interpret retained usage independently of the credential's lifecycle.
    # @param provider [String] provider recorded by the SDK
    # @param calls [Array<Hash>, nil] stored SDK server-tool blocks
    # @return [Integer, nil] search count, or nil when interpretation is unavailable
    def web_search_call_count(provider:, calls:)
      PROVIDERS[provider.to_s]&.fetch(:client_class)&.web_search_call_count(calls)
    end
  end
end
