require "test_helper"

class SearchCredentialsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def credential
    @credential ||= create(:search_credential, user: user)
  end

  test "#index should require authentication" do
    get search_credentials_url
    assert_redirected_to new_session_path
  end

  test "#index should render only the user's credentials" do
    sign_in_as(user)
    credential
    hidden = create(:search_credential, user: other_user)

    get search_credentials_url

    assert_response :success
    assert_select "[data-key='search_credentials.index']"
    assert_select "[data-key='search_credential.#{credential.id}']"
    assert_select "[data-key='search_credential.#{hidden.id}']", count: 0
    assert_select "nav[aria-label='Breadcrumb'] a[href=?]", settings_path, text: "Settings"
  end

  test "#index should explain when no search credentials exist" do
    sign_in_as(user)

    get search_credentials_url

    assert_response :success
    assert_select "[data-key='empty-state']", text: /AI feeds need a search-provider API key to search the web/
    assert_select "[data-key='empty-state']", text: /Non-AI feeds never need one/
  end

  test "#new should render the provider and API key fields" do
    sign_in_as(user)

    get new_search_credential_url

    assert_response :success
    assert_select "[data-key='search_credentials.new']"
    assert_select "[data-key='search_credentials.provider']"
    assert_select "[data-key='search_credentials.credential-data.api_key']"
  end

  test "#create should save and enqueue validation when params are valid" do
    sign_in_as(user)

    assert_difference("SearchCredential.count", 1) do
      assert_enqueued_with(job: SearchCredentialValidationJob) do
        post search_credentials_url, params: {
          search_credential: {
            provider: "serper",
            display_name: "My Search Key",
            credential_data: { api_key: "serper-#{SecureRandom.hex(16)}" }
          }
        }
      end
    end

    saved = SearchCredential.last
    assert_redirected_to search_credential_path(saved)
    assert_equal "pending", saved.state
    assert_equal user, saved.user
  end

  test "#create should generate a name when display_name is blank" do
    sign_in_as(user)

    post search_credentials_url, params: {
      search_credential: {
        provider: "serper",
        display_name: "",
        credential_data: { api_key: "serper-#{SecureRandom.hex(16)}" }
      }
    }

    saved = SearchCredential.last
    assert saved.display_name.start_with?("Serper ")
    assert_equal 3, saved.display_name.split.count
  end

  test "#create should render new with errors on invalid input" do
    sign_in_as(user)

    assert_no_difference("SearchCredential.count") do
      post search_credentials_url, params: {
        search_credential: {
          provider: "serper",
          display_name: "My Search Key",
          credential_data: { api_key: "" }
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "[data-key='search_credentials.new']"
  end

  test "#show should render own credential" do
    sign_in_as(user)

    get search_credential_url(credential)

    assert_response :success
    assert_select "[data-key='search_credential.show']"
  end

  test "#show should place edit and delete actions in the header" do
    sign_in_as(user)

    get search_credential_url(credential)

    assert_response :success
    assert_select "header [data-key='search_credential.edit']"
    assert_select "header form[action=?]", search_credential_path(credential) do
      assert_select "button", text: /Delete/
    end
  end

  test "#show should render the pending state with polling" do
    sign_in_as(user)
    pending = create(:search_credential, user: user, state: :pending)

    get search_credential_url(pending)

    assert_response :success
    assert_select "[data-controller='polling']"
    assert_select "[data-key='search_credential.validating']"
  end

  test "#show should render the validating state with polling" do
    sign_in_as(user)
    validating = create(:search_credential, user: user, state: :validating)

    get search_credential_url(validating)

    assert_response :success
    assert_select "[data-controller='polling']"
    assert_select "[data-key='search_credential.validating']"
  end

  test "#show should render the active state without polling" do
    sign_in_as(user)
    active = create(:search_credential, :active, user: user)

    get search_credential_url(active)

    assert_response :success
    assert_select "[data-controller='polling']", count: 0
    assert_select "[data-key='search_credential.active']"
  end

  test "#show should render the inactive state without polling" do
    sign_in_as(user)
    inactive = create(:search_credential, :inactive, user: user, last_error: "Invalid key")

    get search_credential_url(inactive)

    assert_response :success
    assert_select "[data-controller='polling']", count: 0
    assert_select "[data-key='search_credential.inactive']", text: /Invalid key/
  end

  test "#show should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:search_credential, user: other_user)

    get search_credential_url(other)

    assert_response :not_found
  end

  test "#edit should render the form and key-change copy" do
    sign_in_as(user)

    get edit_search_credential_url(credential)

    assert_response :success
    assert_select "[data-key='search_credentials.edit']"
    assert_select "[data-key='search_credentials.display-name']"
    assert_select "[data-key='search_credentials.credential-data.api_key']"
    assert_select "p", text: /Leave blank to keep the current key and validation state/
  end

  test "#edit should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:search_credential, user: other_user)

    get edit_search_credential_url(other)

    assert_response :not_found
  end

  test "#update should rename without resetting state or enqueuing validation" do
    sign_in_as(user)
    active = create(:search_credential, :active, user: user)
    original_key = active.credential_data["api_key"]

    assert_no_enqueued_jobs only: SearchCredentialValidationJob do
      patch search_credential_url(active), params: {
        search_credential: {
          display_name: "Renamed Search Key",
          credential_data: { api_key: "" }
        }
      }
    end

    active.reload
    assert_redirected_to search_credential_path(active)
    assert_equal "Renamed Search Key", active.display_name
    assert_equal "active", active.state
    assert_equal original_key, active.credential_data["api_key"]
  end

  test "#update should replace a new key, reset state, and enqueue validation" do
    sign_in_as(user)
    active = create(:search_credential, :active, user: user)
    new_key = "serper-#{SecureRandom.hex(16)}"

    assert_enqueued_with(job: SearchCredentialValidationJob) do
      patch search_credential_url(active), params: {
        search_credential: {
          display_name: active.display_name,
          credential_data: { api_key: new_key }
        }
      }
    end

    active.reload
    assert_redirected_to search_credential_path(active)
    assert_equal new_key, active.credential_data["api_key"]
    assert_equal "pending", active.state
  end

  test "#update should render edit with errors on invalid input" do
    sign_in_as(user)

    patch search_credential_url(credential), params: {
      search_credential: {
        display_name: "",
        credential_data: { api_key: "" }
      }
    }

    assert_response :unprocessable_entity
    assert_select "[data-key='search_credentials.edit']"
  end

  test "#update should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:search_credential, user: other_user)

    patch search_credential_url(other), params: {
      search_credential: {
        display_name: "Hacked",
        credential_data: { api_key: "" }
      }
    }

    assert_response :not_found
  end

  test "#destroy should delete own credential" do
    sign_in_as(user)
    credential

    assert_difference("SearchCredential.count", -1) do
      delete search_credential_url(credential)
    end

    assert_redirected_to search_credentials_path
  end

  test "#destroy should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:search_credential, user: other_user)

    assert_no_difference("SearchCredential.count") do
      delete search_credential_url(other)
    end

    assert_response :not_found
  end
end
