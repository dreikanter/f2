require "test_helper"

class AiCredentials::ModelCatalogsControllerTest < ActionDispatch::IntegrationTest
  def credential
    @credential ||= create(:ai_credential, :active, available_models: [{ "id" => "cached-model" }])
  end

  test "#create should require authentication" do
    post ai_credential_model_catalog_path(credential)
    assert_redirected_to new_session_path
  end

  test "#create should refresh an owned catalog while the credential stays active" do
    sign_in_as(credential.user)
    assert_enqueued_with(job: AiModelCatalogRefreshJob) do
      post ai_credential_model_catalog_path(credential)
    end
    assert_redirected_to ai_credential_path(credential)
    follow_redirect!
    assert_select '[data-key="ai_credential.refresh-models"][disabled]'
    assert_includes response.body, "cached-model"
    assert_predicate credential.reload, :active?
  end

  test "#create and show should reject another user's credential" do
    sign_in_as(create(:user))
    assert_no_enqueued_jobs { post ai_credential_model_catalog_path(credential) }
    assert_response :not_found
    get ai_credential_model_catalog_path(credential)
    assert_response :not_found
  end

  test "#show should poll without scheduling work and show the cached list on failure" do
    sign_in_as(credential.user)
    run = credential.refresh_models_async
    assert_no_enqueued_jobs { get ai_credential_model_catalog_path(credential) }
    assert_response :no_content
    run.fail!
    assert_no_enqueued_jobs { get ai_credential_model_catalog_path(credential) }
    assert_response :success
    assert_includes response.body, "cached-model"
    assert_includes response.body, "saved list is still available"
  end

  test "#show validation should render model polling after successful validation" do
    sign_in_as(credential.user)
    credential.refresh_models_async
    get ai_credential_validation_path(credential), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, ai_credential_model_catalog_path(credential)
  end
end
