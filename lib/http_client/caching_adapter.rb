require_relative "faraday_adapter"

module HttpClient
  # A FaradayAdapter that memoizes successful (2xx) GET responses by URL.
  #
  # Built for a single feed-identification run, where matching and per-candidate
  # testing fetch the same source URLs repeatedly. This adapter allows to reuse
  # downloaded web content multiple times in a row, rather than fetching it again.
  #
  # Do NOT use this adapter when you need HTTP-headers drived cache. It is build
  # for a different use case.
  #
  # Only 2xx GETs are cached. Non-2xx responses and raised errors fall through
  # to a live request every time, so a transient blip can't poison the cache or
  # mask a recovery. POST/PUT/DELETE are never cached (inherited unchanged).
  #
  # Keyed on URL alone, which is lossless here: within one run each URL is
  # fetched the same way. Not thread-safe, a cache belongs to one run.
  class CachingAdapter < FaradayAdapter
    DEFAULT_TTL = 60

    CacheEntry = Struct.new(:response, :expires_at) do
      def expired?
        expires_at <= Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
    private_constant :CacheEntry

    def initialize(**options)
      @cache_ttl = options.delete(:cache_ttl) || DEFAULT_TTL
      @cache = {}
      super
    end

    def get(url, headers: {}, options: {})
      entry = @cache[url]
      return entry.response if entry && !entry.expired?

      response = super
      @cache[url] = CacheEntry.new(response, monotonic_time + @cache_ttl) if response.success?
      response
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
