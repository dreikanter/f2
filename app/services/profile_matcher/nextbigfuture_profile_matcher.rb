module ProfileMatcher
  class NextbigfutureProfileMatcher < Base
    input_shape :url
    match_specificity 100

    NEXTBIGFUTURE_DOMAIN = "nextbigfuture.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host == NEXTBIGFUTURE_DOMAIN || uri.host&.end_with?(".#{NEXTBIGFUTURE_DOMAIN}")
    end
  end
end
