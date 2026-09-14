require "test_helper"

class RefreshLlmModelsJobTest < ActiveSupport::TestCase
  teardown { RubyLLM.models.load_from_json }

  def stub_catalog
    stub_request(:get, "https://rubyllm.com/models.json").to_return(
      body: [{ id: "shared-model", name: "Shared model", provider: "openai" }].to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  def job_with_run
    job = RefreshLlmModelsJob.new
    JobRun.create!(job_class: RefreshLlmModelsJob.name, job_id: job.job_id)
    job
  end

  test ".runnable_jobs should include the refresh so dev tools can launch it" do
    assert_includes JobRun.runnable_jobs, RefreshLlmModelsJob
  end

  test "#perform should record the run and how many models it stored" do
    stub_catalog
    job = job_with_run

    job.perform_now

    run = JobRun.sole
    assert_predicate run, :succeeded?
    event = run.events.sole
    assert_equal "job.refresh_llm_models.completed", event.type
    assert_equal 1, event.metadata["model_count"]
  end

  test "#perform should record a failed run" do
    stub_request(:get, "https://rubyllm.com/models.json").to_return(body: "invalid catalog")
    job = job_with_run

    assert_raises(RubyLLM::ModelRegistryError) { job.perform_now }

    assert_predicate JobRun.sole, :failed?
  end
end
