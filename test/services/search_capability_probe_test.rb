require "test_helper"

class SearchCapabilityProbeTest < ActiveSupport::TestCase
  # Answers each provider call from a queue, so a run's checks can be given
  # different vendor responses without touching the network.
  class ScriptedProvider
    attr_reader :keys, :queries

    def initialize(outcomes)
      @outcomes = outcomes
      @keys = []
      @queries = []
    end

    def search(query, max_results: 5)
      @queries << { query: query, max_results: max_results }
      outcome = @outcomes.shift
      raise outcome if outcome.is_a?(StandardError)

      outcome
    end
  end

  def result(title: "Ruby", url: "https://ruby-lang.org", snippet: "A dynamic language")
    WebSearchProvider::Result.new(title: title, url: url, snippet: snippet)
  end

  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def credential
    @credential ||= create(:search_credential, user: dev_user, provider: "serper", display_name: "Serper Probe")
  end

  # Stubs the two seams a run uses: the credential's own provider (live key) and
  # the registry (rejected key).
  def run_probe(live:, rejected:, checks: SearchCapabilityProbe::Runner::CHECKS)
    live_provider = ScriptedProvider.new(live)
    rejected_provider = ScriptedProvider.new(rejected)

    credential.stub(:web_search_provider, live_provider) do
      WebSearchProvider.stub(:for, ->(_name, api_key:) { rejected_provider }) do
        outcome = SearchCapabilityProbe::Runner.new(credential: credential, checks: checks).run
        yield outcome, live_provider, rejected_provider
      end
    end
  end

  def check(outcome, name)
    outcome[:results].find { |entry| entry[:check] == name }
  end

  test ".credential_name should name the credential after the provider label" do
    assert_equal "Serper Probe", SearchCapabilityProbe.credential_name("serper")
    assert_equal "Tavily Probe", SearchCapabilityProbe.credential_name("tavily")
  end

  test ".candidate_credentials should find the credential named after the probe" do
    credential
    assert_equal [credential], SearchCapabilityProbe.candidate_credentials("serper").to_a
  end

  test ".candidate_credentials should ignore a credential of another provider with the same name" do
    create(:search_credential, user: dev_user, provider: "brave", display_name: "Serper Probe")
    assert_empty SearchCapabilityProbe.candidate_credentials("serper")
  end

  test ".candidate_credentials should ignore a probe-named credential owned by a non-dev user" do
    create(:search_credential, user: create(:user), provider: "serper", display_name: "Serper Probe")
    assert_empty SearchCapabilityProbe.candidate_credentials("serper")
  end

  test ".ambiguous_credential_message should say which name to free up" do
    message = SearchCapabilityProbe.ambiguous_credential_message("serper", 2)
    assert_match(/2 dev users/, message)
    assert_match(/"Serper Probe"/, message)
  end

  test ".missing_credential_message should name the exact credential to create" do
    message = SearchCapabilityProbe.missing_credential_message("brave")
    assert_match(/"Brave Probe"/, message)
    assert_match(/Brave credential/, message)
  end

  test "#run should pass every check when the vendor behaves" do
    rejected = [WebSearchProvider::AuthError.new("Serper: HTTP 403")]
    live = [[result, result], [result]]

    run_probe(live: live, rejected: rejected) do |outcome|
      assert outcome[:passed]
      assert_equal %w[PASS PASS PASS], outcome[:results].map { |entry| entry[:status] }
    end
  end

  test "#run should fail the rejection check when a dead key reads as transient" do
    rejected = [WebSearchProvider::ProviderError.new("Brave: HTTP 422")]

    run_probe(live: [[result], [result]], rejected: rejected) do |outcome|
      assert_not outcome[:passed]
      failure = check(outcome, "rejection")
      assert_equal "FAIL", failure[:status]
      assert_match(/not AuthError/, failure[:note])
      assert_equal "Brave: HTTP 422", failure[:evidence][:error]
    end
  end

  test "#run should fail the rejection check when an invalid key is accepted" do
    run_probe(live: [[result], [result]], rejected: [[result]]) do |outcome|
      assert_equal "FAIL", check(outcome, "rejection")[:status]
      assert_match(/invalid key was accepted/, check(outcome, "rejection")[:note])
    end
  end

  test "#run should fail the search check when the response maps to nothing" do
    rejected = [WebSearchProvider::AuthError.new("Serper: HTTP 403")]

    run_probe(live: [[], [result]], rejected: rejected) do |outcome|
      assert_not outcome[:passed]
      assert_match(/no results/, check(outcome, "search")[:note])
    end
  end

  test "#run should fail the search check when mapped fields are blank" do
    rejected = [WebSearchProvider::AuthError.new("Serper: HTTP 403")]
    live = [[result, result(snippet: "")], [result]]

    run_probe(live: live, rejected: rejected) do |outcome|
      failure = check(outcome, "search")
      assert_equal "FAIL", failure[:status]
      assert_match(%r{1/2 results missing mapped fields}, failure[:note])
    end
  end

  test "#run should fail the search check when a result url is not a url" do
    rejected = [WebSearchProvider::AuthError.new("Serper: HTTP 403")]
    live = [[result(url: "not-a-url")], [result]]

    run_probe(live: live, rejected: rejected) do |outcome|
      assert_equal "FAIL", check(outcome, "search")[:status]
    end
  end

  test "#run should send the validation job's own query and cap on the minimal check" do
    rejected = [WebSearchProvider::AuthError.new("Serper: HTTP 403")]

    run_probe(live: [[result], [result]], rejected: rejected) do |outcome, live_provider|
      assert_equal "PASS", check(outcome, "minimal")[:status]
      assert_equal({ query: SearchCredentialValidationJob::VALIDATION_QUERY, max_results: 1 },
                   live_provider.queries.last)
    end
  end

  test "#run should record usage for the billed checks only" do
    rejected = [WebSearchProvider::AuthError.new("Serper: HTTP 403")]

    assert_difference -> { WebSearchUsage.for_credential(credential).count }, 2 do
      run_probe(live: [[result], [result]], rejected: rejected) { |outcome| assert outcome[:passed] }
    end
  end

  test "#run should record a failure rather than raise when a check blows up" do
    rejected = [WebSearchProvider::AuthError.new("Serper: HTTP 403")]
    live = [RuntimeError.new("boom"), [result]]

    run_probe(live: live, rejected: rejected) do |outcome|
      assert_not outcome[:passed]
      assert_equal "FAIL", check(outcome, "search")[:status]
      assert_match(/RuntimeError: boom/, check(outcome, "search")[:note])
    end
  end

  test "#run should time each check" do
    rejected = [WebSearchProvider::AuthError.new("Serper: HTTP 403")]

    run_probe(live: [[result], [result]], rejected: rejected) do |outcome|
      assert(outcome[:results].all? { |entry| entry[:seconds].is_a?(Numeric) })
    end
  end
end
