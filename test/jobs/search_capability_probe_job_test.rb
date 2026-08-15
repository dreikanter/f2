require "test_helper"

class SearchCapabilityProbeJobTest < ActiveJob::TestCase
  def job
    @job ||= SerperCapabilityProbeJob.new
  end

  def job_run
    @job_run ||= create(:job_run, job_class: "SerperCapabilityProbeJob", job_id: job.job_id)
  end

  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def credential
    @credential ||= create(:search_credential, user: dev_user, provider: "serper", display_name: "Serper Probe")
  end

  def outcome
    {
      results: [
        { check: "rejection", status: "PASS", note: "invalid key rejected as AuthError",
          evidence: { error: "Serper: HTTP 403" }, seconds: 0.1 },
        { check: "search", status: "FAIL", note: "no results", evidence: { results: [] }, seconds: 0.2 }
      ],
      passed: false
    }
  end

  def stub_runner(result)
    runner = Minitest::Mock.new
    runner.expect(:run, result)
    SearchCapabilityProbe::Runner.stub(:new, ->(**) { runner }) { yield }
    runner.verify
  end

  test "should register a probe per registered provider" do
    [SerperCapabilityProbeJob, BraveCapabilityProbeJob, TavilyCapabilityProbeJob].each do |klass|
      assert_includes JobRun::RUNNABLE_JOBS, klass
    end

    pinned = [SerperCapabilityProbeJob, BraveCapabilityProbeJob, TavilyCapabilityProbeJob].map { |k| k::PROVIDER }
    assert_equal WebSearchProvider::REGISTRY.keys.sort, pinned.sort
  end

  test "#perform should record a skip naming the credential to create when it is missing" do
    job_run
    job.perform_now

    event = Event.find_by(subject: job_run, type: "job.search_capability_probe.skipped")
    assert_predicate event, :warning?
    assert_includes event.message, '"Serper Probe"'
    assert_equal "Serper Probe", event.metadata["expected_credential_name"]
  end

  test "#perform should not run checks when the credential is missing" do
    job_run
    SearchCapabilityProbe::Runner.stub(:new, ->(**) { raise "should not run" }) do
      job.perform_now
    end

    assert_empty Event.where(subject: job_run, type: "job.search_capability_probe.check")
  end

  test "#perform should refuse to guess when two dev users hold the probe name" do
    job_run
    credential
    create(:search_credential, user: create(:user, :dev), provider: "serper", display_name: "Serper Probe")

    SearchCapabilityProbe::Runner.stub(:new, ->(**) { raise "should not run" }) do
      job.perform_now
    end

    event = Event.find_by(subject: job_run, type: "job.search_capability_probe.skipped")
    assert_includes event.message, "2 dev users"
    assert_empty Event.where(subject: job_run, type: "job.search_capability_probe.check")
  end

  test "#perform should record one event per check plus a summary" do
    job_run
    credential

    stub_runner(outcome) { job.perform_now }

    checks = Event.where(subject: job_run, type: "job.search_capability_probe.check").order(:id)
    assert_equal 2, checks.count
    assert_predicate checks.first, :info?
    assert_equal "Serper: HTTP 403", checks.first.metadata.dig("evidence", "error")
    assert_predicate checks.second, :warning?
    assert_includes checks.second.message, "search: FAIL"

    summary = Event.find_by(subject: job_run, type: "job.search_capability_probe.completed")
    assert_includes summary.message, "rejection=PASS search=FAIL"
    assert_equal false, summary.metadata["passed"]
    assert_equal credential.id, summary.metadata["credential_id"]
    assert_predicate summary, :warning?
  end

  test "#perform should use whichever credential carries the probe name" do
    job_run
    create(:search_credential, user: dev_user, provider: "serper", display_name: "Some Other Key")
    credential

    stub_runner(outcome.merge(passed: true, results: [])) { job.perform_now }

    summary = Event.find_by(subject: job_run, type: "job.search_capability_probe.completed")
    assert_equal credential.id, summary.metadata["credential_id"]
  end
end
