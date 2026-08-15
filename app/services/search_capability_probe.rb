# Checks a web-search integration against the vendor's live API. Fixtures can
# only confirm our reading of a vendor's docs; these checks confirm the vendor
# still behaves that way.
#
# The key comes from a SearchCredential named after the probe, so the checks run
# through the same objects a feed run uses. Two of the three spend a real query,
# billed to that credential and recorded as usage.
module SearchCapabilityProbe
  # The query the credential validation job sends, so the minimal check asks for
  # exactly what a user's key has to satisfy to go active.
  QUERY = SearchCredentialValidationJob::VALIDATION_QUERY

  class << self
    def credential_name(provider)
      "#{WebSearchProvider.label_for(provider)} Probe"
    end

    # Scoped to whoever launched the probe: each run spends billed queries, and
    # display names are unique per user and provider, so the owner is what makes
    # the name resolve to one key.
    def credential_for(provider, user:)
      user.search_credentials.find_by(provider: provider, display_name: credential_name(provider))
    end

    # Says what to create, since the fix is always the same: one credential,
    # this provider, this exact name.
    def missing_credential_message(provider)
      "no search credential named #{credential_name(provider).inspect} on your account — " \
        "add a #{WebSearchProvider.label_for(provider)} credential with that exact name to run this probe"
    end
  end

  class Runner
    CHECKS = %w[rejection search minimal].freeze
    RESULT_URL = %r{\Ahttps?://}

    def initialize(credential:, checks: CHECKS)
      @credential = credential
      @checks = checks
      @results = []
    end

    # Returns { results:, passed: }. Failures are recorded rather than raised:
    # the job is to report what a vendor does, not to stop at the first
    # surprise.
    def run
      @checks.each { |check| record(check) { send("check_#{check}") } }
      { results: @results, passed: @results.none? { |result| result[:status] == "FAIL" } }
    end

    private

    def record(check)
      started = Time.current
      outcome = yield
      @results << { check: check, status: outcome[:status], note: outcome[:note],
                    evidence: outcome[:evidence], seconds: (Time.current - started).round(1) }
    rescue StandardError => e
      @results << { check: check, status: "FAIL", note: "#{e.class}: #{e.message.to_s[0, 300]}",
                    evidence: nil, seconds: (Time.current - started).round(1) }
    end

    # Free, and the check fixtures cannot stand in for: it asks the vendor
    # itself how it turns a dead key away. A ProviderError here means a revoked
    # or exhausted key would read as a passing fault and stay in service.
    def check_rejection
      rejected_provider.search(QUERY, max_results: 1)
      { status: "FAIL", note: "an invalid key was accepted", evidence: nil }
    rescue WebSearchProvider::AuthError => e
      { status: "PASS", note: "invalid key rejected as AuthError", evidence: { error: e.message } }
    rescue WebSearchProvider::Error => e
      { status: "FAIL",
        note: "invalid key raised #{e.class.name.demodulize}, not AuthError — a dead key would read as transient",
        evidence: { error: e.message } }
    end

    # A vendor renaming a response field leaves a working key returning nothing,
    # which looks exactly like a query with no matches.
    def check_search
      results = search(max_results: 3)
      evidence = { results: results.map(&:to_h) }
      return { status: "FAIL", note: "no results for #{QUERY.inspect}", evidence: evidence } if results.empty?

      unlinked = results.reject { |result| result.url.match?(RESULT_URL) }
      if unlinked.any?
        return { status: "FAIL", note: "#{unlinked.size}/#{results.size} results have no usable URL",
                 evidence: evidence }
      end

      # A renamed response field blanks that field on every result, while one
      # sparse result is ordinary — so only a field that never arrives is a
      # mapping failure.
      missing = %i[title snippet].select { |field| results.all? { |result| result.public_send(field).blank? } }
      return { status: "PASS", note: "#{results.size} results, all fields mapped", evidence: evidence } if missing.empty?

      { status: "FAIL", note: "#{missing.join(' and ')} never populated — check the response shape",
        evidence: evidence }
    end

    # The shape SearchCredentialValidationJob sends, down to the one-result cap:
    # a vendor that rejects it can never let a user's credential go active.
    def check_minimal
      results = search(max_results: 1)
      evidence = { results: results.map(&:to_h) }
      return { status: "FAIL", note: "one-result query returned nothing", evidence: evidence } if results.empty?

      { status: "PASS", note: "one-result query accepted", evidence: evidence }
    end

    # Not a key any vendor issued, generated per run so nothing key-shaped is
    # committed. What matters is not that the search fails but how: unless the
    # refusal reaches us as AuthError, a spent credential stays in service and
    # every later run keeps calling it.
    def rejected_provider
      WebSearchProvider.for(@credential.provider, api_key: "f2-probe-#{SecureRandom.hex(8)}")
    end

    # Recorded like any other search: an unaccounted call would make the
    # credential's cost surface lie.
    def search(max_results:)
      WebSearchUsage.record!(credential: @credential)
      @credential.web_search_provider.search(QUERY, max_results: max_results)
    end
  end
end
