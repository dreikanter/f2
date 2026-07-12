# One interface over interchangeable web-search backends, mirroring how
# LlmProvider registers AI providers. `for` builds a named provider around an
# injected API key; each provider turns one vendor's HTTP API into normalized
# WebSearchProvider::Result values, so the vendor is a configuration choice,
# not a caller concern.
#
# Key resolution is interim: until search credentials become a managed model
# (mirroring AiCredential), `default` reads keys from ENV. Providers never read
# ENV themselves — the key is always injected — so that seam moves cleanly to
# credential lookup later.
module WebSearchProvider
  DEFAULT_MAX_RESULTS = 5

  Result = Data.define(:title, :url, :snippet)

  Error = Class.new(StandardError)
  ConfigurationError = Class.new(Error)
  ProviderError = Class.new(Error)

  REGISTRY = {
    "serper" => "Serper",
    "brave" => "Brave",
    "tavily" => "Tavily"
  }.freeze

  # Interim: the env var each provider's key comes from, until search
  # credentials become a managed model. Delete this alongside `default`,
  # `configured?`, and their helpers when that lands.
  ENV_KEYS = {
    "serper" => "SERPER_API_KEY",
    "brave" => "BRAVE_SEARCH_API_KEY",
    "tavily" => "TAVILY_API_KEY"
  }.freeze

  class << self
    def for(name, api_key:)
      class_name = REGISTRY[name.to_s]
      raise ConfigurationError, "unknown web search provider: #{name}" unless class_name

      const_get(class_name).new(api_key: api_key)
    end

    # A usable provider from the interim ENV config, or ConfigurationError.
    def default
      name = default_name
      raise ConfigurationError, "no web search provider configured" unless name

      self.for(name, api_key: env_key(name))
    end

    def configured?
      default
      true
    rescue ConfigurationError
      false
    end

    private

    # WEB_SEARCH_PROVIDER when its key is present, else the first registered
    # provider whose key is set. A named provider without a key resolves to
    # nothing rather than silently falling back to another vendor.
    def default_name
      explicit = ENV["WEB_SEARCH_PROVIDER"].presence
      return env_key(explicit).present? ? explicit : nil if explicit

      REGISTRY.keys.find { |name| env_key(name).present? }
    end

    def env_key(name)
      var = ENV_KEYS[name.to_s]
      ENV[var].presence if var
    end
  end
end
