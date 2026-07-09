class FeedIdentification
  # Wraps a persisted detection candidate (a JSONB hash) so callers read intent
  # (failed?/unreachable?/…) instead of indexing raw string keys.
  class Candidate
    def initialize(attributes)
      @attributes = attributes
    end

    def profile_key
      @attributes["profile_key"]
    end

    def title
      @attributes["title"]
    end

    def posts_found
      @attributes["posts_found"].to_i
    end

    def failed?
      test_status == "failed"
    end

    def unreachable?
      test_status == "unreachable"
    end

    private

    def test_status
      @attributes["test_status"]
    end
  end
end
