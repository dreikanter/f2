module ProfileMatcher
  class NextbigfutureProfileMatcher < Base
    match_specificity 100

    NEXTBIGFUTURE_DOMAINS = ["nextbigfuture.com", "www.nextbigfuture.com"].freeze

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      NEXTBIGFUTURE_DOMAINS.include?(uri.host)
    end
  end
end
