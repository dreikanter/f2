require "digest"

module HttpClient
  class CachingAdapter < Base
    DEFAULT_CACHE_EXPIRATION = 10.minutes.in_seconds

    attr_reader :adapter, :cache_store, :cache_expires_in

    def initialize(adapter:, cache_store:, cache_expires_in: DEFAULT_CACHE_EXPIRATION)
      @adapter = adapter
      @cache_store = cache_store
      @cache_expires_in = cache_expires_in
      super(adapter.options)
    end

    def get(url, headers: {}, options: {})
      key = cache_key(:get, url, headers, options)
      cached_response = read_from_cache(key)
      return cached_response if cached_response

      response = adapter.get(url, headers: headers, options: options)
      write_to_cache(key, response)
      response
    end

    def post(url, **)
      adapter.post(url, **)
    end

    def put(url, **)
      adapter.put(url, **)
    end

    def delete(url, **)
      adapter.delete(url, **)
    end

    private

    def cache_key(method, url, headers, request_options)
      "http_client:#{Digest::SHA256.hexdigest("#{method}:#{url}")}"
    end

    def read_from_cache(key)
      cached_data = cache_store.read(key)
      return nil unless cached_data

      Response.new(
        status: cached_data[:status],
        body: cached_data[:body],
        headers: cached_data[:headers]
      )
    end

    def write_to_cache(key, response)
      cache_store.write(
        key,
        { status: response.status, body: response.body, headers: response.headers },
        expires_in: cache_expires_in
      )
    end
  end
end
