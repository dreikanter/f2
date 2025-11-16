module CachingHelpers
  # Temporarily enables memory cache storage within the block,
  # then reverts to the original cache store.
  #
  # Useful for testing rate limiting or other cache-dependent features
  # in an environment that normally uses null cache store.
  #
  # Example:
  #   with_caching do
  #     # Rate limiting will work here
  #     post session_url, params: { ... }
  #   end
  def with_caching
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original_cache
  end
end
