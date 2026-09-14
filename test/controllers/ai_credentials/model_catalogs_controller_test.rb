require "test_helper"

class AiCredentials::ModelCatalogsControllerTest < ActionDispatch::IntegrationTest
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

  test "#create should require authentication and ownership" do
    post ai_credential_model_catalog_path(credential)
    assert_redirected_to new_session_path

    sign_in_as(create(:user))
    assert_no_difference -> { refresh_jobs.count } do
      post ai_credential_model_catalog_path(credential)
    end
    assert_response :not_found
    get ai_credential_model_catalog_path(credential)
    assert_response :not_found
  end

  test "#create should share one refresh and its result across credentials" do
    first = credential
    second = create(:ai_credential, :active)
    original_credentials = AiCredential.order(:id).map(&:attributes)
    create(:llm_model, model_id: "shared-model", name: "Old name")
    request = stub_request(:get, "https://rubyllm.com/models.json").to_return(
      body: [{ id: "shared-model", name: "New name", provider: "openai", modalities: { output: ["text"] } }].to_json,
      headers: { "Content-Type" => "application/json" }
    )
    sign_in_as(first.user)
    post ai_credential_model_catalog_path(first)
    assert_redirected_to ai_credential_path(first)
    assert_equal 1, refresh_jobs.count

    sign_in_as(second.user)
    assert_no_difference -> { refresh_jobs.count } do
      post ai_credential_model_catalog_path(second)
    end
    assert_no_difference -> { refresh_jobs.count } do
      get ai_credential_model_catalog_path(second)
    end
    assert_response :no_content

    perform_refresh
    get ai_credential_model_catalog_path(second)

    assert_response :success
    assert_select 'turbo-stream[action="replace"][target="ai-credential-model-catalog"]' do
      assert_select '[data-key="ai_credential.model.name"]', text: "New name"
      assert_select '[data-controller="polling"]', count: 0
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
    post ai_credential_model_catalog_path(credential)

    assert_raises(RubyLLM::ModelRegistryError) { perform_refresh }
    get ai_credential_model_catalog_path(credential)

    assert_response :success
    assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Couldn't refresh models/
    assert_select '[data-key="ai_credential.model.name"]', text: "saved-model"
    assert_equal original, credential.reload.attributes
  end

  test "#create should refresh independently of credential validation and preserve the return link" do
    sign_in_as(credential.user)
    feed = create(:feed, user: credential.user, ai_credential: credential)
    validation = credential.validate_async(AiCredentialValidationJob)

    assert_difference -> { refresh_jobs.count }, 1 do
      post ai_credential_model_catalog_path(credential, feed_id: feed.id)
    end

    assert_redirected_to ai_credential_path(credential, feed_id: feed.id)
    assert_predicate validation.reload, :running?
    assert_equal [], refresh_jobs.last.arguments.fetch("arguments")
  end
end
