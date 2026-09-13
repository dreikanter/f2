require "test_helper"

class AiCredentials::ValidationsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= regular_user
  end

  def credential
    @credential ||= create(:ai_credential, user: user, active: false)
  end

  test "#show should require authentication" do
    get ai_credential_validation_url(credential)
    assert_redirected_to new_session_path
  end

  test "#show should return no content while still validating" do
    sign_in_as(user)
    credential.validate_async(AiCredentialValidationJob)

    get ai_credential_validation_url(credential),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :no_content
    assert_empty response.body
  end

  test "#show should render the validation turbo stream once it resolves" do
    sign_in_as(user)
    active = create(:ai_credential, :active, user: user)

    get ai_credential_validation_url(active),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, "ai-credential-show"
  end

  test "#show should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:ai_credential, user: other_user)

    get ai_credential_validation_url(other),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :not_found
  end

  test "#show should render the partial with feed_id when feed_id is provided" do
    sign_in_as(user)
    active = create(:ai_credential, :active, user: user)
    draft = create(:feed, :draft, user: user)

    get ai_credential_validation_url(active, feed_id: draft.id),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "ai-credential-show"
    assert_includes response.body, edit_feed_path(draft.id)
  end

  test "#show should render an overdue validation without mutating records" do
    sign_in_as(user)
    run = credential.validate_async(AiCredentialValidationJob)
    original_credential = credential.reload.attributes
    original_run = run.reload.attributes

    travel_to run.deadline_at + 1.second do
      assert_no_enqueued_jobs do
        get ai_credential_validation_url(credential), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_select '[data-key="ai_credential.inactive"]', text: /check timed out/
    assert_select '[data-key="ai_credential.validating"]', count: 0
    assert_equal original_credential, credential.reload.attributes
    assert_equal original_run, run.reload.attributes
  end

  test "#show should render validation failure while retaining an active credential" do
    sign_in_as(user)
    active = create(:ai_credential, :active, user: user)
    run = active.validate_async(AiCredentialValidationJob)
    run.timeout!

    get ai_credential_validation_url(active), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select '[data-credential-state="active"]'
    assert_select '[data-key="ai_credential.validation_error"]', text: /check timed out/
    assert_select '[data-key="ai_credential.validating"]', count: 0
  end


  test "#show should render inactive content when only a catalog refresh or unrelated operation is running" do
    sign_in_as(user)
    OperationRun.start!(subject: credential, kind: :models_refresh)
    OperationRun.start!(subject: credential, kind: :groups_refresh)

    get ai_credential_validation_url(credential), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select '[data-key="ai_credential.inactive"]'
    assert_select '[data-key="ai_credential.validating"]', count: 0
  end
end
