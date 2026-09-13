require "test_helper"

class SearchCredentials::ValidationsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= regular_user
  end

  def credential
    @credential ||= create(:search_credential, user: user, active: false)
  end

  test "#show should require authentication" do
    get search_credential_validation_url(credential)

    assert_redirected_to new_session_path
  end

  test "#show should render an inactive credential without a validation run" do
    sign_in_as(user)

    get search_credential_validation_url(credential),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select '[data-key="search_credential.inactive"]'
    assert_select '[data-key="search_credential.validating"]', count: 0
  end

  test "#show should poll revalidation then render the result" do
    sign_in_as(user)
    active = create(:search_credential, :active, user: user)
    run = active.validate_async(SearchCredentialValidationJob)

    get search_credential_validation_url(active),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :no_content
    assert_empty response.body
    assert_predicate active.reload, :active?

    run.succeed!

    get search_credential_validation_url(active),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_select 'turbo-stream[action="update"][target="search-credential-show"]' do
      assert_select '[data-credential-state="active"]'
      assert_select '[data-key="search_credential.validating"]', count: 0
    end
  end

  test "#show should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:search_credential, user: other_user)

    get search_credential_validation_url(other),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :not_found
  end

  test "#show should render an overdue validation without mutating records" do
    sign_in_as(user)
    run = credential.validate_async(SearchCredentialValidationJob)
    original_credential = credential.reload.attributes
    original_run = run.reload.attributes

    travel_to run.deadline_at + 1.second do
      assert_no_enqueued_jobs do
        get search_credential_validation_url(credential), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_select '[data-key="search_credential.inactive"]', text: /check timed out/
    assert_select '[data-key="search_credential.validating"]', count: 0
    assert_equal original_credential, credential.reload.attributes
    assert_equal original_run, run.reload.attributes
  end

  test "#show should render a timeout while retaining an active credential" do
    sign_in_as(user)
    active = create(:search_credential, :active, user: user)
    run = active.validate_async(SearchCredentialValidationJob)
    travel_to(run.deadline_at) { run.timeout! }

    get search_credential_validation_url(active), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select '[data-credential-state="active"]'
    assert_select '[data-key="search_credential.validation_error"]', text: /check timed out/
    assert_select '[data-key="search_credential.validating"]', count: 0
  end
end
