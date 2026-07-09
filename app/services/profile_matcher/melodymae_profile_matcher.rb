module ProfileMatcher
  class MelodymaeProfileMatcher < Base
    match_specificity 100

    MELODYMAE_DOMAIN = "melodymae.co.uk"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      [MELODYMAE_DOMAIN, "www.#{MELODYMAE_DOMAIN}"].include?(uri.host)
    end
  end
end
