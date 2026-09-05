# Free published metadata is advisory and matched by provider plus exact model ID.
class PublishedModelMetadata
  URL = "https://models.dev/api.json".freeze
  CACHE_KEY = "published-model-metadata/v1".freeze
  MAX_BYTES = 32.megabytes

  def lookup(provider, model_id)
    provider_id = provider == "moonshot" ? "moonshotai" : provider
    entry = catalog.dig(provider_id, "models", model_id)
    return unless entry.is_a?(Hash)

    metadata = { "source" => "models.dev" }
    %w[tool_call structured_output].each do |key|
      metadata[key] = entry[key] if entry[key] == true || entry[key] == false
    end
    modalities = entry["modalities"]
    if modalities.is_a?(Hash)
      outputs = modalities["output"]
      metadata["output_modalities"] = outputs if outputs.is_a?(Array) && outputs.all? { |value| value.is_a?(String) }
    end
    limits = entry["limit"]
    if limits.is_a?(Hash)
      metadata["context_window"] = positive_number(limits["context"])
      metadata["max_output_tokens"] = positive_number(limits["output"])
    end
    prices = entry["cost"]
    if prices.is_a?(Hash)
      metadata["pricing"] = prices.slice("input", "output", "cache_read", "cache_write")
                                   .select { |_key, value| value.is_a?(Numeric) && value >= 0 }
    end
    metadata.compact
  end

  private

  def catalog
    @catalog ||= cached_catalog
  end

  def cached_catalog
    previous = Rails.cache.read(CACHE_KEY) || {}
    return previous if Rails.cache.read("#{CACHE_KEY}/fresh")

    response = HttpClient.build(timeout: 15, follow_redirects: false).get(URL)
    raise HttpClient::Error, "Model metadata HTTP #{response.status}" unless response.success?
    raise HttpClient::Error, "Model metadata is too large" if response.body.bytesize > MAX_BYTES

    data = JSON.parse(response.body)
    unless data.is_a?(Hash) && data.values.all? { |provider| provider.is_a?(Hash) && provider["models"].is_a?(Hash) }
      raise HttpClient::Error, "Invalid model metadata catalog"
    end

    Rails.cache.write(CACHE_KEY, data, expires_in: 7.days)
    Rails.cache.write("#{CACHE_KEY}/fresh", true, expires_in: 1.day)
    data
  rescue HttpClient::Error, JSON::ParserError => e
    Rails.error.report(e)
    Rails.cache.write("#{CACHE_KEY}/fresh", true, expires_in: 1.hour)
    previous
  end

  def positive_number(value)
    value if value.is_a?(Integer) && value.positive?
  end
end
