# Service for managing feed identification cache keys
class FeedIdentificationCache
  # Generates a cache key for feed identification
  # @param user_id [Integer] the user ID
  # @param url [String] the feed URL
  # @return [String] the cache key
  def self.key_for(user_id, url)
    "feed_identification/#{user_id}/#{Digest::SHA256.hexdigest(url)}"
  end
end
