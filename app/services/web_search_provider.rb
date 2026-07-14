# One interface over interchangeable web-search backends, mirroring how
# LlmProvider registers AI providers. `for` builds a named provider around an
# API key supplied by a managed SearchCredential; each provider turns one
# vendor's HTTP API into normalized WebSearchProvider::Result values, so the
# vendor is a credential choice, not a caller concern.
module WebSearchProvider
  DEFAULT_MAX_RESULTS = 5

  Result = Data.define(:title, :url, :snippet)
  Configuration = Data.define(:class_name, :label, :cents_per_1k_requests)

  Error = Class.new(StandardError)
  ConfigurationError = Class.new(Error)
  ProviderError = Class.new(Error)
  # A rejected or exhausted API key (HTTP 401/402/403), as opposed to a
  # transient ProviderError: retrying is pointless and the credential behind
  # the key should be deactivated, so callers must be able to tell them apart.
  AuthError = Class.new(Error)

  REGISTRY = {
    "serper" => Configuration.new(class_name: "Serper", label: "Serper", cents_per_1k_requests: 100),
    "brave" => Configuration.new(class_name: "Brave", label: "Brave", cents_per_1k_requests: 500),
    "tavily" => Configuration.new(class_name: "Tavily", label: "Tavily", cents_per_1k_requests: 800)
  }.freeze

  class << self
    def for(name, api_key:)
      configuration = configuration_for(name)
      const_get(configuration.class_name).new(api_key: api_key)
    end

    def label_for(name)
      configuration_for(name).label
    end

    def cents_per_1k_requests_for(name)
      configuration_for(name).cents_per_1k_requests
    end

    def options_for_select
      REGISTRY.map { |name, configuration| [configuration.label, name] }
    end

    private

    def configuration_for(name)
      REGISTRY.fetch(name.to_s) do
        raise ConfigurationError, "unknown web search provider: #{name}"
      end
    end
  end
end
