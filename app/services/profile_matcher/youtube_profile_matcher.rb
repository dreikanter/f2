module ProfileMatcher
  class YoutubeProfileMatcher < Base
    input_shape :url
    match_specificity 100

    YOUTUBE_DOMAINS = %w[youtube.com youtu.be].freeze

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      YOUTUBE_DOMAINS.any? { |domain| uri.host&.end_with?(domain) }
    end
  end
end
