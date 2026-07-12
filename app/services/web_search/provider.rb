module WebSearch
  # Registry of search backends, keyed by provider name. Each provider is a
  # thin client that turns one vendor's HTTP API into normalized Results.
  module Provider
    REGISTRY = {
      "serper" => "Serper",
      "brave" => "Brave",
      "tavily" => "Tavily"
    }.freeze

    def self.for(name)
      class_name = REGISTRY[name.to_s]
      raise ConfigurationError, "unknown web search provider: #{name}" unless class_name

      const_get(class_name).new
    end

    # The provider answering when the caller names none: WEB_SEARCH_PROVIDER
    # if set, otherwise the first registered provider with an API key present.
    def self.default
      explicit = ENV["WEB_SEARCH_PROVIDER"].presence
      return self.for(explicit) if explicit

      provider = REGISTRY.keys.lazy.map { |name| self.for(name) }.find(&:configured?)
      raise ConfigurationError, "no web search provider configured" unless provider

      provider
    end
  end
end
