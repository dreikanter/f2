# Shared HTTP caching for free published model catalogs.
class PublishedModelCatalog
  MAX_BYTES = 32.megabytes

  def self.fetch(url, cache_key)
    previous = Rails.cache.read(cache_key) || {}
    return previous if Rails.cache.read("#{cache_key}/fresh")

    response = HttpClient.build(timeout: 15, follow_redirects: false).get(url)
    raise HttpClient::Error, "Model metadata HTTP #{response.status}" unless response.success?
    raise HttpClient::Error, "Model metadata is too large" if response.body.bytesize > MAX_BYTES

    data = JSON.parse(response.body)
    raise HttpClient::Error, "Invalid model metadata catalog" unless data.is_a?(Hash) && yield(data)

    Rails.cache.write(cache_key, data, expires_in: 7.days)
    Rails.cache.write("#{cache_key}/fresh", true, expires_in: 1.day)
    data
  rescue HttpClient::Error, JSON::ParserError => e
    Rails.error.report(e)
    Rails.cache.write("#{cache_key}/fresh", true, expires_in: 1.hour)
    previous
  end
end
