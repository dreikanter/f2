require "test_helper"

class LlmCapabilityProbeJobTest < ActiveJob::TestCase
  def job
    @job ||= AnthropicCapabilityProbeJob.new
  end

  def job_run
    @job_run ||= create(:job_run, job_class: "AnthropicCapabilityProbeJob", job_id: job.job_id)
  end

  test "should register both provider probes as runnable jobs" do
    assert_includes JobRun::RUNNABLE_JOBS, AnthropicCapabilityProbeJob
    assert_includes JobRun::RUNNABLE_JOBS, KimiCapabilityProbeJob
  end

  test "should pin one provider and model per job" do
    assert_equal %w[anthropic claude-sonnet-4-6],
                 [AnthropicCapabilityProbeJob::PROVIDER, AnthropicCapabilityProbeJob::MODEL]
    assert_equal %w[moonshot kimi-k2.5], [KimiCapabilityProbeJob::PROVIDER, KimiCapabilityProbeJob::MODEL]
  end

  test "#perform should record a skip event when the API key is not configured" do
    job_run

    LlmCapabilityProbe::Provider.stub(:configured?, false) do
      job.perform_now
    end

    events = Event.for_subject(job_run).where(type: "job.llm_capability_probe.skipped")
    assert_equal 1, events.count
    assert_predicate events.first, :warning?
  end

  test "#perform should record one event per check with full evidence plus a summary" do
    job_run

    outcome = {
      results: [
        { check: "plain", status: "PASS", note: "ok", evidence: "pong", seconds: 0.1 },
        { check: "schema", status: "FAIL", note: "boom", evidence: { items: [] }, seconds: 0.2 }
      ],
      passed: false
    }
    runner = Minitest::Mock.new
    runner.expect(:run, outcome)

    LlmCapabilityProbe::Provider.stub(:configured?, true) do
      LlmCapabilityProbe::Provider.stub(:build, ->(key) { key }) do
        LlmCapabilityProbe::Runner.stub(:new, ->(**) { runner }) do
          job.perform_now
        end
      end
    end

    checks = Event.for_subject(job_run).where(type: "job.llm_capability_probe.check").order(:id)
    assert_equal 2, checks.count
    assert_equal "pong", checks.first.metadata["evidence"]
    assert_predicate checks.first, :info?
    assert_predicate checks.second, :warning?
    assert_includes checks.second.message, "schema: FAIL"

    summary = Event.for_subject(job_run).find_by(type: "job.llm_capability_probe.completed")
    assert_includes summary.message, "plain=PASS schema=FAIL"
    assert_equal false, summary.metadata["passed"]
    assert_predicate summary, :warning?
    runner.verify
  end
end
