require "digest"

module HttpClient
  class CachingAdapter < Base
    DEFAULT_CACHE_EXPIRATION = 10 * 60 # 10 minutes in seconds

    attr_reader :adapter, :cache_store, :cache_expires_in

    def initialize(adapter:, cache_store:, cache_expires_in: DEFAULT_CACHE_EXPIRATION)
      @adapter = adapter
      @cache_store = cache_store
      @cache_expires_in = cache_expires_in
      super(adapter.options)
    end

    def get(url, headers: {}, options: {})
      cache_key = generate_cache_key(:get, url, headers, options)
      cached_response = read_from_cache(cache_key)
      return cached_response if cached_response

      response = adapter.get(url, headers: headers, options: options)
      write_to_cache(cache_key, response)
      response
    end

    def post(url, body: nil, headers: {}, options: {})
      adapter.post(url, body: body, headers: headers, options: options)
    end

    def put(url, body: nil, headers: {}, options: {})
      adapter.put(url, body: body, headers: headers, options: options)
    end

    def delete(url, headers: {}, options: {})
      adapter.delete(url, headers: headers, options: options)
    end

    private

    def generate_cache_key(method, url, headers, request_options)
      "http_client:#{Digest::SHA256.hexdigest("#{method}:#{url}")}"
    end

    def read_from_cache(cache_key)
      cached_data = cache_store.read(cache_key)
      return nil unless cached_data

      Response.new(
        status: cached_data[:status],
        body: cached_data[:body],
        headers: cached_data[:headers]
      )
    end

    def write_to_cache(cache_key, response)
      cache_store.write(
        cache_key,
        { status: response.status, body: response.body, headers: response.headers },
        expires_in: cache_expires_in
      )
    end
  end
end
