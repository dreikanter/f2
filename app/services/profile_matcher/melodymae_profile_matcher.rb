module ProfileMatcher
  class MelodymaeProfileMatcher < Base
    input_shape :url
    match_specificity 100

    MELODYMAE_DOMAIN = "melodymae.co.uk"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host == MELODYMAE_DOMAIN || uri.host&.end_with?(".#{MELODYMAE_DOMAIN}")
    end
  end
end
