module ProfileMatcher
  # Matches public X/Twitter profile URLs: twitter.com/<handle> and
  # x.com/<handle> (also www/mobile subdomains). Reserved paths like /home or
  # /search are rejected so they fall through to the generic profiles.
  class TwitterProfileMatcher < Base
    input_shape :url
    match_specificity 100

    HOSTS = %w[twitter.com www.twitter.com mobile.twitter.com x.com www.x.com].freeze
    RESERVED = %w[home search explore notifications messages settings i compose intent hashtag share login signup].freeze
    HANDLE = /\A[A-Za-z0-9_]{1,15}\z/

    def match?
      return false if input.blank?

      uri = URI.parse(input.strip)
      return false unless HOSTS.include?(uri.host)

      segments = uri.path.to_s.split("/").reject(&:empty?)
      name = segments.first

      name.present? && !RESERVED.include?(name.downcase) && name.match?(HANDLE)
    rescue URI::InvalidURIError
      false
    end
  end
end
