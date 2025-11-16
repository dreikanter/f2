module CachingHelpers
  # Temporarily enables memory cache storage within the block,
  # then reverts to the original cache store.
  #
  # Useful for testing cache-dependent features in an environment
  # that normally uses null cache store.
  #
  # Example:
  #   with_caching do
  #     # Caching will work here
  #     Rails.cache.write("key", "value")
  #   end
  def with_caching
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original_cache
  end
end
