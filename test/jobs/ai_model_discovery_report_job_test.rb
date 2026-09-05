require "test_helper"

class AiModelDiscoveryReportJobTest < ActiveJob::TestCase
  def job
    @job ||= AiModelDiscoveryReportJob.new
  end

  def job_run
    @job_run ||= create(:job_run, job_class: job.class.name, job_id: job.job_id)
  end

  def credential
    @credential ||= create(:ai_credential, :active, provider: "openai",
                            credential_data: { "api_key" => "staging-report-secret" })
  end

  def run_report
    job_run
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("staging")) { job.perform_now }
    job_run.events.sole.metadata
  end

  def stub_models(status: 200, body: nil)
    body ||= { data: [{ id: "new-model", object: "model", owned_by: "openai" }] }
    stub_request(:get, "https://api.openai.com/v1/models")
      .with(headers: { "Authorization" => "Bearer staging-report-secret" })
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  test "#perform should list models with an existing staging credential without inference or credential mutation" do
    credential.update!(available_models: [{ "id" => "cached-model" }])
    original_attributes = credential.attributes
    request = stub_models

    report = nil
    assert_no_difference [-> { LlmUsage.count }, -> { Feed.count }, -> { Post.count }] do
      report = run_report
    end

    result = report.fetch("results").find { |entry| entry["provider"] == "openai" }
    assert_equal "PASS", result["status"]
    assert_equal ["new-model"], result.fetch("models").pluck("id")
    assert_equal 1, result["models_without_capability_metadata"]
    assert_equal "staging", report["environment"]
    assert_equal Gem.loaded_specs.fetch("ruby_llm").version.to_s, report["ruby_llm_version"]
    assert_equal original_attributes, credential.reload.attributes
    assert_not_includes report.to_json, "staging-report-secret"
    assert_not_includes report.to_json, credential.user.email
    assert_requested request, times: 1
    assert_not_requested :post, /./
  end

  test "#perform should use only one active credential per provider" do
    credential
    create(:ai_credential, :active, provider: "openai", created_at: 1.minute.from_now)
    create(:ai_credential, :inactive, provider: "moonshot")
    request = stub_models

    report = run_report

    assert_requested request, times: 1
    assert_equal "SKIP", report.fetch("results").find { |entry| entry["provider"] == "moonshot" }["status"]
  end

  test "#perform should report missing credentials without contacting providers" do
    report = run_report

    assert_equal LlmProvider.names.sort, report.fetch("results").pluck("provider").sort
    assert report.fetch("results").all? { |result| result["status"] == "SKIP" }
    assert_not_requested :any, /./
  end

  test "#perform should report an empty model listing as a failed check" do
    credential
    stub_models(body: { data: [] })

    result = run_report.fetch("results").find { |entry| entry["provider"] == "openai" }

    assert_equal "FAIL", result["status"]
    assert_equal 0, result["model_count"]
    assert_predicate job_run.events.sole, :warning?
  end

  test "#perform should keep failed credentials active and omit provider error text from the report" do
    credential
    stub_models(status: 401, body: { error: { message: "Rejected staging-report-secret" } })

    report = run_report
    result = report.fetch("results").find { |entry| entry["provider"] == "openai" }

    assert_equal "FAIL", result["status"]
    assert_equal "LlmClient::AuthError", result["error_class"]
    assert_equal LlmProvider.names.size, report.fetch("results").size
    assert_predicate credential.reload, :active?
    assert_not_includes report.to_json, "staging-report-secret"
    assert_not_requested :post, /./
  end

  test "#perform should reject execution outside staging before accessing credentials" do
    credential
    job_run

    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      assert_raises(RuntimeError) { job.perform_now }
    end

    assert_predicate job_run.reload, :failed?
    assert_empty job_run.events
    assert_not_requested :any, /./
  end
end
