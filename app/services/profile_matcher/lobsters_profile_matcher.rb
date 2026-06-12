module ProfileMatcher
  class LobstersProfileMatcher < Base
    input_shape :url
    match_specificity 100

    LOBSTERS_DOMAIN = "lobste.rs"

    def match?
      return false if input.blank?

      URI.parse(input).host == LOBSTERS_DOMAIN
    end
  end
end
