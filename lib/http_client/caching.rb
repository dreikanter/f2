require_relative "base"

module HttpClient
  # Wraps another HttpClient with a short-lived, in-memory, URL-keyed cache for
  # GET requests, so a single feed-identification run fetches each source URL at
  # most once across matching and per-candidate testing.
  #
  # Only successful (2xx) responses are cached. Non-2xx responses and raised
  # errors are never cached, so a transient blip during matching can't poison a
  # later test or mask a recovery. Entries expire after a short TTL.
  #
  # Scoped to one run and held in process memory — deliberately not for
  # scheduled refreshes, which must always hit the network.
  class Caching < Base
    DEFAULT_TTL = 60

    def initialize(client, ttl: DEFAULT_TTL)
      super()
      @client = client
      @ttl = ttl
      @entries = {}
      @mutex = Mutex.new
    end

    def get(url, headers: {}, options: {})
      cached = read(url)
      return cached if cached

      response = @client.get(url, headers: headers, options: options)
      write(url, response) if response.success?
      response
    end

    def post(url, body: nil, headers: {}, options: {})
      @client.post(url, body: body, headers: headers, options: options)
    end

    def put(url, body: nil, headers: {}, options: {})
      @client.put(url, body: body, headers: headers, options: options)
    end

    def delete(url, headers: {}, options: {})
      @client.delete(url, headers: headers, options: options)
    end

    private

    def read(url)
      @mutex.synchronize do
        entry = @entries[url]
        next nil if entry.nil?

        if monotonic_now >= entry[:expires_at]
          @entries.delete(url)
          next nil
        end

        entry[:response]
      end
    end

    def write(url, response)
      @mutex.synchronize do
        @entries[url] = { response: response, expires_at: monotonic_now + @ttl }
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
