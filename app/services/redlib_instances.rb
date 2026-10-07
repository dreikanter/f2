class RedlibInstances
  class Error < StandardError; end

  SOURCE_URL = "https://raw.githubusercontent.com/redlib-org/redlib-instances/main/instances.json"

  # Discovery is lazy: no background traffic until score lookups are used.
  # @return [Array<String>] public HTTPS instance URLs
  def urls
    Rails.cache.fetch("redlib/instances/v1", expires_in: 1.hour) { fetch_urls }
  end

  private

  def fetch_urls
    response = HttpClient.build(timeout: 5).get(SOURCE_URL)
    raise Error, "Redlib directory returned HTTP #{response.status}" unless response.success?

    data = JSON.parse(response.body)
    instances = data["instances"] if data.is_a?(Hash)
    raise Error, "Invalid Redlib directory" unless instances.is_a?(Array)

    urls = instances.filter_map do |instance|
      url = instance["url"] if instance.is_a?(Hash)
      url.delete_suffix("/") if url.is_a?(String) && url.start_with?("https://") && PublicUrl.safe?(url)
    end.uniq
    raise Error, "Redlib directory contains no public HTTPS instances" if urls.empty?

    urls
  rescue HttpClient::Error, JSON::ParserError => e
    raise Error, "Cannot fetch Redlib directory: #{e.message}"
  end
end
