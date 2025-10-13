# HTTP Client abstraction layer
#
# Provides a standardized interface over HTTP libraries (currently Faraday).
# This abstraction allows swapping HTTP implementations (Faraday -> Net::HTTP,
# HTTParty, etc.) without changing application code, and ensures consistent error
# handling across the app.
#
require_relative "http_client/response"
require_relative "http_client/base"
require_relative "http_client/faraday_adapter"
require_relative "http_client/caching_adapter"

module HttpClient
  class Error < StandardError; end
  class ConnectionError < Error; end
  class TimeoutError < Error; end
  class TooManyRedirectsError < Error; end

  def self.build(options = {})
    adapter_class = options.delete(:adapter) || default_adapter_class
    cache_store = options.delete(:cache_store)
    cache_expires_in = options.delete(:cache_expires_in)
    adapter = adapter_class.new(**options)

    if cache_store
      CachingAdapter.new(
        adapter: adapter,
        cache_store: cache_store,
        cache_expires_in: cache_expires_in
      )
    else
      adapter
    end
  end

  def self.default_adapter_class
    FaradayAdapter
  end
end
