require "test_helper"

class KimiExperimentJobTest < ActiveJob::TestCase
  test "should register all three experiments as runnable jobs" do
    assert_includes JobRun::RUNNABLE_JOBS, KimiWebSearchWireJob
    assert_includes JobRun::RUNNABLE_JOBS, KimiStructuredOutputJob
    assert_includes JobRun::RUNNABLE_JOBS, KimiClientToolJob
  end

  test "#perform should record a skip event when the API key is not configured" do
    job = KimiWebSearchWireJob.new
    run = create(:job_run, job_class: "KimiWebSearchWireJob", job_id: job.job_id)

    LlmCapabilityProbe::Provider.stub(:configured?, false) { job.perform_now }

    assert_equal 1, Event.for_subject(run).where(type: "job.kimi_experiment.skipped").count
  end

  test "KimiWebSearchWireJob should record per-round steps and an engagement verdict" do
    job = KimiWebSearchWireJob.new
    run = create(:job_run, job_class: "KimiWebSearchWireJob", job_id: job.job_id)
    steps = [{ round: 1, status: 200, finish_reason: "stop", content: "I cannot browse", grounded: false }]

    LlmCapabilityProbe::Provider.stub(:configured?, true) do
      KimiExperiment.stub(:web_search_steps, steps) { job.perform_now }
    end

    assert_equal 2, Event.for_subject(run).where(type: "job.kimi_experiment.step").count
    summary = Event.for_subject(run).find_by(type: "job.kimi_experiment.completed")
    assert_includes summary.message, "auto=ignored forced=ignored"
    assert_predicate summary, :warning?
  end

  test "KimiStructuredOutputJob should tally outcomes per mode" do
    job = KimiStructuredOutputJob.new
    run = create(:job_run, job_class: "KimiStructuredOutputJob", job_id: job.job_id)
    attempts = [
      { mode: "none", attempt: 1, status: 200, outcome: "fenced_json", content: "```json{}```" },
      { mode: "json_object", attempt: 1, status: 200, outcome: "clean_json", content: "{}" }
    ]

    LlmCapabilityProbe::Provider.stub(:configured?, true) do
      KimiExperiment.stub(:structured_output_attempts, attempts) { job.perform_now }
    end

    assert_equal 2, Event.for_subject(run).where(type: "job.kimi_experiment.attempt").count
    summary = Event.for_subject(run).find_by(type: "job.kimi_experiment.completed")
    assert_includes summary.message, "none: 0/1 clean"
    assert_includes summary.message, "json_object: 1/1 clean"
  end

  test "KimiClientToolJob should record invocation count and grounding" do
    job = KimiClientToolJob.new
    run = create(:job_run, job_class: "KimiClientToolJob", job_id: job.job_id)
    result = { invocations: 1, content: "https://rubyonrails.org/x", grounded: true }

    LlmCapabilityProbe::Provider.stub(:configured?, true) do
      KimiExperiment.stub(:client_tool_attempt, result) { job.perform_now }
    end

    summary = Event.for_subject(run).find_by(type: "job.kimi_experiment.completed")
    assert_includes summary.message, "1 invocation(s), grounded=true"
    assert_predicate summary, :info?
    assert_equal 1, summary.metadata["invocations"]
  end
end
