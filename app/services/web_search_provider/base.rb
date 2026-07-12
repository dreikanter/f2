module WebSearchProvider
  # Contract for a search backend. Subclasses declare ENDPOINT and implement
  # `request` (perform the vendor HTTP call) and `map_results` (normalize the
  # vendor payload into Results); everything else is shared here. The API key
  # is injected at construction — providers never read it from the environment.
  class Base
    MAX_RESULTS = (1..10)
    TIMEOUT = 10

    def initialize(api_key:)
      @api_key = api_key
    end

    def search(query, max_results: DEFAULT_MAX_RESULTS)
      raise ConfigurationError, "#{provider_name} API key missing" unless configured?

      count = max_results.to_i.clamp(MAX_RESULTS)
      response = request(query, count)
      raise ProviderError, "#{provider_name}: HTTP #{response.status}" unless response.success?

      parse(response.body).first(count)
    rescue HttpClient::Error => e
      raise ProviderError, "#{provider_name}: #{e.message}"
    end

    def configured?
      api_key.present?
    end

    private

    attr_reader :api_key

    def request(query, count)
      raise NotImplementedError, "#{self.class} must implement #request"
    end

    def map_results(json)
      raise NotImplementedError, "#{self.class} must implement #map_results"
    end

    def parse(body)
      map_results(JSON.parse(body.to_s))
    rescue JSON::ParserError => e
      raise ProviderError, "#{provider_name}: unparseable response (#{e.message})"
    end

    def provider_name
      self.class.name.demodulize
    end

    def http
      HttpClient.build(timeout: TIMEOUT)
    end
  end
end
