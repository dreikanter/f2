module ProfileMatcher
  class YoutubeProfileMatcher < Base
    input_shape :url
    match_specificity 100

    YOUTUBE_DOMAINS = %w[youtube.com www.youtube.com youtu.be www.youtu.be].freeze

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      YOUTUBE_DOMAINS.include?(uri.host)
    end
  end
end
