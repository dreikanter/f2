module ProfileMatcher
  class RedditProfileMatcher < Base
    input_shape :url
    match_specificity 50

    REDDIT_DOMAINS = %w[reddit.com www.reddit.com old.reddit.com].freeze
    REDDIT_PATH_PATTERN = %r{\A/(r|user)/[^/]+}

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      REDDIT_DOMAINS.include?(uri.host) && uri.path.match?(REDDIT_PATH_PATTERN)
    end
  end
end
