class FeedIdentification
  # Wraps a persisted detection candidate (a JSONB hash) so callers read intent
  # (failed?/unreachable?/…) instead of indexing raw string keys.
  class Candidate
    # Self-test verdicts, as persisted under "test_status". CandidateTester
    # mints them.
    PASSED = "passed"
    FAILED = "failed"
    UNREACHABLE = "unreachable"

    def initialize(attributes)
      @attributes = attributes
    end

    def profile_key
      @attributes["profile_key"]
    end

    def title
      @attributes["title"]
    end

    # The discovered feed URL the candidate was tested against. Absent when
    # the input identified directly.
    def resolved_url
      @attributes["resolved_url"]
    end

    def posts_found
      @attributes["posts_found"].to_i
    end

    def passed?
      test_status == PASSED
    end

    def failed?
      test_status == FAILED
    end

    def unreachable?
      test_status == UNREACHABLE
    end

    private

    def test_status
      @attributes["test_status"]
    end
  end
end
