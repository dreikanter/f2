# One interface over interchangeable web-search backends, mirroring how
# LlmClient::Adapter abstracts LLM providers. Callers get back normalized
# Result values regardless of which vendor answered, so the provider is a
# deployment choice (API keys in ENV), not a caller concern.
module WebSearch
  DEFAULT_MAX_RESULTS = 5

  Result = Data.define(:title, :url, :snippet)

  Error = Class.new(StandardError)
  ConfigurationError = Class.new(Error)
  ProviderError = Class.new(Error)

  def self.search(query, provider: nil, max_results: DEFAULT_MAX_RESULTS)
    raise ArgumentError, "query must not be blank" if query.blank?

    resolved = provider ? Provider.for(provider) : Provider.default
    resolved.search(query.to_s.strip, max_results: max_results)
  end

  def self.configured?
    Provider.default.configured?
  rescue ConfigurationError
    false
  end
end
