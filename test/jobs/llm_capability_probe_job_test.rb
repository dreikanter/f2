require "test_helper"

class LlmCapabilityProbeJobTest < ActiveJob::TestCase
  def job
    @job ||= LlmCapabilityProbeJob.new
  end

  def job_run
    @job_run ||= create(:job_run, job_class: "LlmCapabilityProbeJob", job_id: job.job_id)
  end

  test "should be registered as a runnable job" do
    assert_includes JobRun::RUNNABLE_JOBS, LlmCapabilityProbeJob
  end

  test "#perform should record a skip event per pair when no API keys are configured" do
    job_run

    LlmCapabilityProbe::Provider.stub(:configured?, false) do
      job.perform_now
    end

    events = Event.for_subject(job_run).where(type: "job.llm_capability_probe.skipped")
    assert_equal LlmCapabilityProbeJob::CANDIDATE_PAIRS.size, events.count
    assert events.all?(&:warning?)
  end

  test "#perform should run the probe and record results for configured pairs" do
    job_run

    outcome = {
      results: [{ check: "plain", status: "PASS", note: "ok", evidence: "secret-payload", seconds: 0.1 }],
      passed: true,
      transcript_path: "tmp/llm_probe/test.json"
    }
    runner = Minitest::Mock.new
    LlmCapabilityProbeJob::CANDIDATE_PAIRS.size.times { runner.expect(:run, outcome) }

    LlmCapabilityProbe::Provider.stub(:configured?, true) do
      LlmCapabilityProbe::Provider.stub(:build, ->(key) { key }) do
        LlmCapabilityProbe::Runner.stub(:new, ->(**) { runner }) do
          job.perform_now
        end
      end
    end

    events = Event.for_subject(job_run).where(type: "job.llm_capability_probe.completed")
    assert_equal LlmCapabilityProbeJob::CANDIDATE_PAIRS.size, events.count
    event = events.first
    assert_includes event.message, "plain=PASS"
    assert_equal "tmp/llm_probe/test.json", event.metadata["transcript"]
    assert_not_includes event.metadata["results"].first.keys, "evidence"
    runner.verify
  end
end
