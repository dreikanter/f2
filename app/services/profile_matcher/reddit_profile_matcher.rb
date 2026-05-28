module ProfileMatcher
  class RedditProfileMatcher < Base
    input_shape :url
    match_specificity 50

    REDDIT_DOMAINS = %w[reddit.com www.reddit.com old.reddit.com].freeze
    REDDIT_PATH_PATTERN = %r{\A/(r|user)/[^/]+}
    SHORT_SUBREDDIT = %r{\Ar/[A-Za-z0-9_]+\z}i
    SHORT_USER      = %r{\Auser/[A-Za-z0-9_-]+\z}i

    def match?
      return false if input.blank?

      stripped = input.strip
      return true if stripped.match?(SHORT_SUBREDDIT)
      return true if stripped.match?(SHORT_USER)

      uri = URI.parse(stripped)
      REDDIT_DOMAINS.include?(uri.host) && uri.path.match?(REDDIT_PATH_PATTERN)
    end
  end
end
