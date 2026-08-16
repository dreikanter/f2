require "test_helper"

class LlmCapabilityProbeJobTest < ActiveJob::TestCase
  def operator
    @operator ||= create(:user, :dev)
  end

  def job
    @job ||= AnthropicCapabilityProbeJob.new(operator)
  end

  def credential
    @credential ||= create(:ai_credential, user: operator, provider: "anthropic", display_name: "AnthropicCapabilityProbe")
  end

  def job_run
    @job_run ||= create(:job_run, job_class: "AnthropicCapabilityProbeJob", job_id: job.job_id)
  end

  test "should register every provider probe as a runnable job" do
    assert_includes JobRun::RUNNABLE_JOBS, AnthropicCapabilityProbeJob
    assert_includes JobRun::RUNNABLE_JOBS, KimiCapabilityProbeJob
    assert_includes JobRun::RUNNABLE_JOBS, OpenAiCapabilityProbeJob
  end

  test "should pin one provider and model per job" do
    assert_equal %w[anthropic claude-sonnet-4-6],
                 [AnthropicCapabilityProbeJob::PROVIDER, AnthropicCapabilityProbeJob::MODEL]
    assert_equal %w[moonshot kimi-k2.6], [KimiCapabilityProbeJob::PROVIDER, KimiCapabilityProbeJob::MODEL]
    assert_equal %w[openai gpt-5-mini], [OpenAiCapabilityProbeJob::PROVIDER, OpenAiCapabilityProbeJob::MODEL]
  end

  test "every probe should pin a model its provider can actually be configured for" do
    JobRun::RUNNABLE_JOBS.select { |job| job < LlmCapabilityProbeJob }.each do |job|
      assert_includes LlmProvider.names, job::PROVIDER,
                      "#{job.name} pins unregistered provider #{job::PROVIDER}"
      assert LlmClient::RateTable.rate_for(provider: job::PROVIDER, model: job::MODEL),
             "#{job.name} pins #{job::MODEL}, which has no rate entry to price a run"
    end
  end

  test ".credential_name should name the credential after the job" do
    assert_equal "AnthropicCapabilityProbe", AnthropicCapabilityProbeJob.credential_name
    assert_equal "KimiCapabilityProbe", KimiCapabilityProbeJob.credential_name
    assert_equal "OpenAiCapabilityProbe", OpenAiCapabilityProbeJob.credential_name
  end

  test ".credential_for should find the credential named after the job" do
    assert_equal credential, AnthropicCapabilityProbeJob.credential_for(operator)
  end

  test ".credential_for should ignore a credential of another provider with the same name" do
    create(:ai_credential, user: operator, provider: "openrouter", display_name: "AnthropicCapabilityProbe")

    assert_nil AnthropicCapabilityProbeJob.credential_for(operator)
  end

  test ".missing_credential_message should name the exact credential to create" do
    message = AnthropicCapabilityProbeJob.missing_credential_message

    assert_match(/"AnthropicCapabilityProbe"/, message)
    assert_match(/Anthropic credential/, message)
  end

  test ".description should mark up the credential the probe needs" do
    assert_includes AnthropicCapabilityProbeJob.description, "<code>AnthropicCapabilityProbe</code>"
    assert_includes KimiCapabilityProbeJob.description, "<code>KimiCapabilityProbe</code>"
    assert_includes OpenAiCapabilityProbeJob.description, "<code>OpenAiCapabilityProbe</code>"
    assert_predicate AnthropicCapabilityProbeJob.description, :html_safe?
  end

  test ".runnable_arguments should ask the dev area for the user who pressed Run" do
    assert_equal [operator], AnthropicCapabilityProbeJob.runnable_arguments(operator)
  end

  test "#perform should record a skip naming the credential to create when it is missing" do
    job_run
    job.perform_now

    event = Event.find_by(subject: job_run, type: "job.llm_capability_probe.skipped")
    assert_predicate event, :warning?
    assert_includes event.message, '"AnthropicCapabilityProbe"'
    assert_equal "AnthropicCapabilityProbe", event.metadata["expected_credential_name"]
  end

  test "#perform should ignore a probe-named credential owned by someone else" do
    job_run
    create(:ai_credential, user: create(:user, :dev), provider: "anthropic", display_name: "AnthropicCapabilityProbe")

    LlmCapabilityProbe::Runner.stub(:new, ->(**) { raise "should not run" }) do
      job.perform_now
    end

    assert Event.exists?(subject: job_run, type: "job.llm_capability_probe.skipped")
  end

  test "#perform should record one event per check with full evidence plus a summary" do
    job_run
    credential

    outcome = {
      results: [
        { check: "plain", status: "PASS", note: "ok", evidence: "pong", seconds: 0.1 },
        { check: "schema", status: "FAIL", note: "boom", evidence: { items: [] }, seconds: 0.2 }
      ],
      passed: false
    }
    runner = Minitest::Mock.new
    runner.expect(:run, outcome)

    LlmCapabilityProbe::Runner.stub(:new, ->(**) { runner }) do
      job.perform_now
    end

    checks = Event.where(subject: job_run, type: "job.llm_capability_probe.check").order(:id)
    assert_equal 2, checks.count
    assert_equal "pong", checks.first.metadata["evidence"]
    assert_predicate checks.first, :info?
    assert_predicate checks.second, :warning?
    assert_includes checks.second.message, "schema: FAIL"

    summary = Event.find_by(subject: job_run, type: "job.llm_capability_probe.completed")
    assert_includes summary.message, "plain=PASS schema=FAIL"
    assert_equal credential.id, summary.metadata["credential_id"]
    assert_equal false, summary.metadata["passed"]
    assert_predicate summary, :warning?
    runner.verify
  end
end
