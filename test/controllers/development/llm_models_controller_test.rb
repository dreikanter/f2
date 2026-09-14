require "test_helper"

class Development::LlmModelsControllerTest < ActionDispatch::IntegrationTest
  test "#show should require authentication" do
    get development_llm_models_path

    assert_redirected_to new_session_path
  end

  test "#show should require dev permission" do
    sign_in_as(regular_user)
    get development_llm_models_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#show should count stored models per provider" do
    create(:llm_model, provider: "openai")
    create(:llm_model, provider: "openai", unlisted_at: Time.current)
    sign_in_as(dev_user)

    get development_llm_models_path

    assert_response :success
    assert_select '[data-key="llm_models.provider.openai"]', text: /1 \(\+1 unlisted\)/
  end

  test "#show should report an empty catalog" do
    sign_in_as(dev_user)

    get development_llm_models_path

    assert_response :success
    assert_select '[data-key="empty-state"]'
    assert_select '[data-key="llm_models.outcome"]'
  end

  test "#show should report the last refresh outcome" do
    LlmModelRefresh.current.update!(refreshed_at: 1.hour.ago, failed_at: 1.minute.ago)
    sign_in_as(dev_user)

    get development_llm_models_path

    assert_response :success
    assert_select '[data-key="llm_models.outcome"]', text: /Failed/
  end

  test "#show should offer a refresh run" do
    sign_in_as(dev_user)

    get development_llm_models_path

    assert_response :success
    assert_select "form[action=?] button[data-key=?]",
                  development_job_job_runs_path(RefreshLlmModelsJob.name),
                  "development.llm_models.refresh"
  end
end
