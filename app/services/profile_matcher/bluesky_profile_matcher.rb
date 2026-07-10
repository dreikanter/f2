module ProfileMatcher
  # Matches public Bluesky profile URLs: bsky.app/profile/<handle-or-DID>.
  # Other bsky.app paths (search, feeds, settings) fall through to the
  # generic profiles.
  class BlueskyProfileMatcher < Base
    match_specificity 100

    HOSTS = %w[bsky.app www.bsky.app].freeze
    HANDLE = Loader::BlueskyLoader::HANDLE
    DID = Loader::BlueskyLoader::DID

    def match?
      return false if input.blank?

      uri = URI.parse(input.strip)
      return false unless HOSTS.include?(uri.host)

      segments = uri.path.to_s.split("/").reject(&:empty?)
      return false unless segments.first == "profile"

      actor = segments.second.to_s
      actor.match?(HANDLE) || actor.match?(DID)
    rescue URI::InvalidURIError
      false
    end
  end
end
