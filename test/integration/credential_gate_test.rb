require "test_helper"

# Integration test for the credential gate as form-submit buttons. The gate
# names each missing credential type so the feed can detour to the relevant
# setup page without losing the draft.
class CredentialGateTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  test "credential gate asks only for AI credentials when no credentials exist" do
    sign_in_as(user)

    post feed_previews_path, params: { profile_key: "llm", "params" => { "prompt" => "https://example.com" } }

    assert_response :success
    assert_select "[data-key='credentials.gate']" do
      assert_select "button[type='submit'][name='commit'][value='save_as_draft_and_add_credentials']",
                    text: /Add AI credentials/
      assert_select "button[value='save_as_draft_and_add_search_credentials']", count: 0
      assert_select "[data-key='credentials.gate.help']",
                    text: /save this feed as a draft and bring you back after setup/
    end
  end

  test "credential gate does not require optional search credentials" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: [{ "id" => "claude-sonnet-4-6" }])

    post feed_previews_path, params: { profile_key: "llm", "params" => { "prompt" => "https://example.com" },
                                           ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6" }

    assert_response :success
    assert_select "button[value='save_as_draft_and_add_credentials']", count: 0
    assert_select "[data-key='credentials.gate']", count: 0
    assert_predicate user.feed_previews.last, :pending?
    assert_nil user.feed_previews.last.search_credential_id
  end

  test "credential gate does not include direct credential links" do
    sign_in_as(user)

    post feed_previews_path, params: { profile_key: "llm", "params" => { "prompt" => "https://example.com" } }

    assert_response :success
    assert_select "[data-key='credentials.gate'] a[href*='/ai_credentials/new']", false
    assert_select "[data-key='credentials.gate'] a[href*='/search_credentials/new']", false
  end
end
