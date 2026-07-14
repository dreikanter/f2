# One interface over interchangeable web-search backends, mirroring how
# LlmProvider registers AI providers. `for` builds a named provider around an
# API key supplied by a managed SearchCredential; each provider turns one
# vendor's HTTP API into normalized WebSearchProvider::Result values, so the
# vendor is a credential choice, not a caller concern.
module WebSearchProvider
  DEFAULT_MAX_RESULTS = 5

  Result = Data.define(:title, :url, :snippet)

  Error = Class.new(StandardError)
  ConfigurationError = Class.new(Error)
  ProviderError = Class.new(Error)
  # A rejected or exhausted API key (HTTP 401/402/403), as opposed to a
  # transient ProviderError: retrying is pointless and the credential behind
  # the key should be deactivated, so callers must be able to tell them apart.
  AuthError = Class.new(Error)

  REGISTRY = {
    "serper" => "Serper",
    "brave" => "Brave",
    "tavily" => "Tavily"
  }.freeze

  def self.for(name, api_key:)
    class_name = REGISTRY[name.to_s]
    raise ConfigurationError, "unknown web search provider: #{name}" unless class_name

    const_get(class_name).new(api_key: api_key)
  end
end
