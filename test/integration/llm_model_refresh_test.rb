require "test_helper"

class LlmModelRefreshTest < ActionDispatch::IntegrationTest
  def queue_adapter_for_test
    ActiveJob::QueueAdapters::SolidQueueAdapter.new
  end

  teardown { RubyLLM.models.load_from_json }

  def credential
    @credential ||= create(:ai_credential, :active)
  end

  def refresh_jobs
    SolidQueue::Job.where(class_name: RefreshLlmModelsJob.name)
  end

  def perform_refresh
    worker = create(:solid_queue_process)
    SolidQueue::ReadyExecution.claim(["default"], 1, worker.id).sole.perform
  end

  test "#perform should share one refresh and its result across credentials" do
    first = credential
    second = create(:ai_credential, :active)
    original_credentials = AiCredential.order(:id).map(&:attributes)
    create(:llm_model, model_id: "shared-model", name: "Old name")
    request = stub_request(:get, "https://rubyllm.com/models.json").to_return(
      body: [{ id: "shared-model", name: "New name", provider: "openai", modalities: { output: ["text"] } }].to_json,
      headers: { "Content-Type" => "application/json" }
    )
    RefreshLlmModelsJob.perform_later
    assert_equal 1, refresh_jobs.count

    assert_no_difference -> { refresh_jobs.count } do
      RefreshLlmModelsJob.perform_later
    end

    perform_refresh
    [first, second].each do |current|
      sign_in_as(current.user)
      get ai_credential_path(current)

      assert_response :success
      assert_select '[data-key="ai_credential.model.name"]', text: "New name"
      assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Updated .* ago/
    end
    assert_equal ["shared-model"], FeedAiSettingsComponent.new(feed: build(:feed, user: first.user), form: nil)
      .models_by_credential.fetch(first.id.to_s).pluck("id")
    assert_equal original_credentials, AiCredential.order(:id).map(&:attributes)
    assert_requested request, times: 1
    assert_not_requested :get, "https://api.openai.com/v1/models"
  end

  test "#show should report a failed refresh and retain models and credential usability" do
    create(:llm_model, model_id: "saved-model")
    sign_in_as(credential.user)
    original = credential.attributes
    stub_request(:get, "https://rubyllm.com/models.json").to_return(body: "invalid catalog")
    RefreshLlmModelsJob.perform_later

    assert_raises(RubyLLM::ModelRegistryError) { perform_refresh }
    get ai_credential_path(credential)

    assert_response :success
    assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Couldn't refresh models/
    assert_select '[data-key="ai_credential.model.name"]', text: "saved-model"
    assert_equal original, credential.reload.attributes
  end

  test "#show should retain the latest outcome and update time after queue history is pruned" do
    sign_in_as(credential.user)
    stub_request(:get, "https://rubyllm.com/models.json").to_return(
      { body: "invalid catalog" },
      { body: [{ id: "shared-model", name: "Shared model", provider: "openai" }].to_json, headers: { "Content-Type" => "application/json" } },
      { body: "invalid catalog" }
    )
    RefreshLlmModelsJob.perform_later
    assert_raises(RubyLLM::ModelRegistryError) { perform_refresh }

    RefreshLlmModelsJob.perform_later
    perform_refresh
    updated_at = LlmModelRefresh.current.refreshed_at

    travel 2.days do
      SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0)
      assert_empty refresh_jobs.finished
      assert_equal 1, refresh_jobs.failed.count

      get ai_credential_path(credential)
      assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Updated .* ago/
      assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Couldn't refresh models/, count: 0
      assert_equal updated_at, LlmModelRefresh.current.refreshed_at

      RefreshLlmModelsJob.perform_later
      assert_raises(RubyLLM::ModelRegistryError) { perform_refresh }
      refresh_jobs.destroy_all

      get ai_credential_path(credential)
      assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Couldn't refresh models/
      assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Updated .* ago/
      assert_equal updated_at, LlmModelRefresh.current.refreshed_at
    end
  end
end
