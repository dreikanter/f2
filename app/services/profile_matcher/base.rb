module ProfileMatcher
  # Base class for feed profile matchers.
  #
  # Subclasses declare their ranking weight at the class level:
  #
  #   class MyMatcher < Base
  #     match_specificity 10       # integer; higher = more specific
  #   end
  #
  # The detector ranks matched profiles by this declaration. The matcher
  # itself implements #match?, which returns true if the profile applies
  # to the input (and optional fetched body). Matchers are deterministic:
  # detection never calls an LLM (the detector enforces this).
  class Base
    class << self
      def match_specificity(value = nil)
        if value.nil?
          @match_specificity || raise(NotImplementedError, "#{name} must declare match_specificity via the class-level DSL")
        else
          raise ArgumentError, "match_specificity must be an Integer, got #{value.inspect}" unless value.is_a?(Integer)

          @match_specificity = value
        end
      end

      # Profile key derived from the class name (e.g.
      # ProfileMatcher::RssProfileMatcher → "rss"). Subclasses may
      # override if the convention doesn't apply.
      def profile_key
        name.demodulize.gsub(/ProfileMatcher$/, "").underscore
      end
    end

    attr_reader :input, :fetched_body

    # @param input [String] the user's source URL
    # @param fetched_body [String, nil] the body of the URL when
    #   FeedIdentificationFetcher already fetched it; nil otherwise
    def initialize(input, fetched_body = nil)
      @input = input
      @fetched_body = fetched_body
    end

    def match?
      raise NotImplementedError, "Subclasses must implement #match?"
    end
  end
end
