module ProfileMatcher
  # Base class for matchers that key off the URL host alone. Subclasses
  # declare the domains they own; each is matched bare and with a "www."
  # prefix:
  #
  #   class XkcdProfileMatcher < DomainMatcher
  #     match_specificity 100
  #     match_domains "xkcd.com"
  #   end
  #
  # Matchers needing path, handle, or body rules subclass Base and write
  # their own #match?.
  class DomainMatcher < Base
    class << self
      def match_domains(*domains)
        raise ArgumentError, "match_domains requires at least one domain" if domains.empty?

        @hosts = domains.flat_map { |domain| [domain, "www.#{domain}"] }.freeze
      end

      def hosts
        @hosts || raise(NotImplementedError, "#{name} must declare its domains via match_domains")
      end
    end

    # Invalid URLs raise URI::InvalidURIError rather than matching nothing:
    # detection treats an unparseable source as a user error, not a miss.
    def match?
      return false if input.blank?

      self.class.hosts.include?(URI.parse(input).host)
    end
  end
end
