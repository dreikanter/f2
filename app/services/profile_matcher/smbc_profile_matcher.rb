module ProfileMatcher
  class SmbcProfileMatcher < Base
    match_specificity 100

    HOSTS = %w[smbc-comics.com www.smbc-comics.com].freeze

    def match?
      return false if input.blank?

      HOSTS.include?(URI.parse(input).host)
    end
  end
end
