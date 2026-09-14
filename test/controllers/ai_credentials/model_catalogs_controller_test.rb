require "test_helper"

class AiCredentials::ModelCatalogsControllerTest < ActionDispatch::IntegrationTest
  include OpenaiModelsTestHelpers

  def credential
    @credential ||= create(:ai_credential, :active, available_models: [{ "id" => "cached-model" }])
  end

  test "#create should require authentication" do
    post ai_credential_model_catalog_path(credential)
    assert_redirected_to new_session_path
  end

  test "#create should ignore refresh requests for inactive credentials" do
    credential.update!(active: false)
    sign_in_as(credential.user)

    assert_no_enqueued_jobs { post ai_credential_model_catalog_path(credential) }

    assert_redirected_to ai_credential_path(credential)
  end

  test "#create should queue a refresh and poll until the snapshot is ready" do
    sign_in_as(credential.user)
    post ai_credential_model_catalog_path(credential)

    run = credential.latest_operation_run(:models_refresh)
    assert_enqueued_with(job: AiModelCatalogRefreshJob, args: [run])
    assert_redirected_to ai_credential_path(credential)
    get ai_credential_model_catalog_path(credential)
    assert_response :no_content

    run.succeed! { |current| current.update!(available_models: [{ "id" => "refreshed-model" }]) }
    get ai_credential_model_catalog_path(credential)

    assert_response :success
    assert_select "#ai-credential-model-catalog", text: /refreshed-model/
    assert_select 'button[data-key="ai_credential.refresh-models"]:not([disabled])'
  end

  test "#create and show should reject another user's credential" do
    sign_in_as(create(:user))
    assert_no_enqueued_jobs { post ai_credential_model_catalog_path(credential) }
    assert_response :not_found
    get ai_credential_model_catalog_path(credential)
    assert_response :not_found
  end

  test "#show should replace the credential state and explanation after a rejected key" do
    sign_in_as(credential.user)
    stub_openai_models(key: credential.credential_data.fetch("api_key"), fixture: "invalid_key", status: 401)
    post ai_credential_model_catalog_path(credential)
    get ai_credential_path(credential)
    assert_select '[data-credential-state="active"]'

    AiModelCatalogRefreshJob.perform_now(credential.latest_operation_run(:models_refresh))

    assert_no_enqueued_jobs { get ai_credential_model_catalog_path(credential) }

    assert_response :success
    assert_select 'turbo-stream[action="update"][target="ai-credential-show"]' do
      assert_select '[data-credential-state="inactive"]'
      assert_select '[data-key="ai_credential.inactive"]', text: "OpenAI rejected this API key. Check or replace it."
      assert_select '[data-key="ai_credential.refresh-models"]', count: 0
    end
  end

  test "#show should poll without scheduling work and show the cached list on failure" do
    sign_in_as(credential.user)
    credential.update!(models_refreshed_at: 1.hour.ago)
    run = OperationRun.start!(subject: credential, kind: :models_refresh, timeout: 15.minutes)
    assert_no_enqueued_jobs { get ai_credential_model_catalog_path(credential) }
    assert_response :no_content
    run.fail!
    assert_no_enqueued_jobs { get ai_credential_model_catalog_path(credential) }
    assert_response :success
    assert_select "#ai-credential-model-catalog", text: /cached-model/
    assert_select '[data-key="ai_credential.models-refresh-status"]', text: /saved list is still available/
  end

  test "#show should clear a refresh failure only after another catalog refresh" do
    sign_in_as(credential.user)
    stub_openai_models(key: credential.credential_data.fetch("api_key"), fixture: "unavailable", status: 503)
    post ai_credential_model_catalog_path(credential)
    refresh_run = credential.latest_operation_run(:models_refresh)
    AiModelCatalogRefreshJob.perform_now(refresh_run)

    get ai_credential_model_catalog_path(credential)
    assert_response :success
    assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Couldn't refresh models/

    travel 1.minute do
      stub_openai_models(key: credential.credential_data.fetch("api_key"))
      validation_run = credential.validate_async(AiCredentialValidationJob)
      AiCredentialValidationJob.perform_now(validation_run)

      assert_no_enqueued_jobs { get ai_credential_model_catalog_path(credential) }

      assert_response :success
      assert_select "#ai-credential-model-catalog", text: /cached-model/
      assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Couldn't refresh models/

      post ai_credential_model_catalog_path(credential)
      AiModelCatalogRefreshJob.perform_now(credential.latest_operation_run(:models_refresh))
      get ai_credential_model_catalog_path(credential)

      assert_response :success
      assert_select "#ai-credential-model-catalog", text: /future-openai-model/
      assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Updated .* ago\./
      assert_select '[data-key="ai_credential.models-refresh-status"]', text: /Couldn't refresh models/, count: 0
    end
  end

  test "#show validation should poll a refresh started after successful validation" do
    sign_in_as(credential.user)
    stub_openai_models(key: credential.credential_data.fetch("api_key"))
    validation_run = credential.validate_async(AiCredentialValidationJob)
    AiCredentialValidationJob.perform_now(validation_run)
    credential.refresh_models_async(force: true)

    get ai_credential_validation_path(credential), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select 'turbo-stream[action="update"][target="ai-credential-show"]' do
      assert_select '[data-controller="polling"][data-polling-endpoint-value=?]', ai_credential_model_catalog_path(credential)
    end
  end

  test "#show should keep polling when validation supersedes a refresh" do
    feed = create(:feed, user: credential.user, ai_credential: credential)
    sign_in_as(credential.user)
    post ai_credential_model_catalog_path(credential, feed_id: feed.id)
    validation_run = nil
    stub_openai_models(key: credential.credential_data.fetch("api_key")) do
      validation_run = credential.validate_async(AiCredentialValidationJob)
    end
    AiModelCatalogRefreshJob.perform_now(credential.latest_operation_run(:models_refresh))

    get ai_credential_model_catalog_path(credential, feed_id: feed.id)

    assert_response :success
    assert_select 'turbo-stream[action="update"][target="ai-credential-show"]' do
      assert_select '[data-controller="polling"][data-polling-endpoint-value=?]', ai_credential_validation_path(credential, feed_id: feed.id) do
        assert_select '[data-key="ai_credential.validating"]'
        assert_select '[data-polling-target="timeoutMessage"] a[href=?]', ai_credential_path(credential, feed_id: feed.id)
      end
    end

    stub_openai_models(key: credential.credential_data.fetch("api_key"))
    AiCredentialValidationJob.perform_now(validation_run)
    get ai_credential_validation_path(credential, feed_id: feed.id)

    assert_response :success
    assert_select '[data-credential-state="active"]'
    assert_select "#ai-credential-model-catalog", text: /cached-model/
    assert_select '[data-controller="polling"]', count: 0
  end

  test "#show should preserve the return to feed link through refresh and polling" do
    feed = create(:feed, user: credential.user, ai_credential: credential)
    sign_in_as(credential.user)
    post ai_credential_model_catalog_path(credential, feed_id: feed.id)
    assert_redirected_to ai_credential_path(credential, feed_id: feed.id)
    follow_redirect!
    assert_select '[data-controller="polling"][data-polling-endpoint-value=?]', ai_credential_model_catalog_path(credential, feed_id: feed.id)

    credential.latest_operation_run(:models_refresh).succeed!
    get ai_credential_model_catalog_path(credential, feed_id: feed.id)

    assert_response :success
    assert_select 'a[data-key="ai_credential.return-to"][href=?]', edit_feed_path(feed)
    assert_select "form[action=?]", ai_credential_model_catalog_path(credential, feed_id: feed.id)
  end
end
