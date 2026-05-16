module ProfileMatcher
  # Base class for feed profile matchers.
  #
  # Subclasses declare metadata at the class level via the DSL:
  #
  #   class MyMatcher < Base
  #     input_shape :url           # one of :url, :handle, :query, :any
  #     match_specificity 10       # integer; higher = more specific
  #     depends_on_ai false        # default false; AI matchers set true
  #   end
  #
  # The detector reads these declarations to filter matchers by input
  # shape, rank them, and skip the AI-using ones during the no-AI
  # detection phase. The matcher itself implements #match?, which returns
  # true if the profile applies to the input (and optional fetched body).
  class Base
    INPUT_SHAPES = %i[url handle query any].freeze

    class << self
      def input_shape(value = nil)
        if value.nil?
          @input_shape || raise(NotImplementedError, "#{name} must declare input_shape via the class-level DSL")
        else
          raise ArgumentError, "input_shape must be one of #{INPUT_SHAPES.inspect}, got #{value.inspect}" unless INPUT_SHAPES.include?(value)

          @input_shape = value
        end
      end

      def match_specificity(value = nil)
        if value.nil?
          @match_specificity || raise(NotImplementedError, "#{name} must declare match_specificity via the class-level DSL")
        else
          raise ArgumentError, "match_specificity must be an Integer, got #{value.inspect}" unless value.is_a?(Integer)

          @match_specificity = value
        end
      end

      def depends_on_ai(value = nil)
        if value.nil?
          @depends_on_ai.nil? ? false : @depends_on_ai
        else
          @depends_on_ai = value ? true : false
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

    # @param input [String] the user's raw input (URL, handle, or query)
    # @param fetched_body [String, nil] the body of the URL when input_shape is :url
    #   and FeedDetailsFetcher already fetched it; nil otherwise
    def initialize(input, fetched_body = nil)
      @input = input
      @fetched_body = fetched_body
    end

    def match?
      raise NotImplementedError, "Subclasses must implement #match?"
    end
  end
end
