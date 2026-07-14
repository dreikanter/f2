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

  test "credential gate renders both setup buttons when both credential types are missing" do
    sign_in_as(user)

    get feed_preview_path(profile_key: "llm", "params" => { "prompt" => "https://example.com" })

    assert_response :success
    assert_select "[data-key='credentials.gate']" do
      assert_select "button[type='submit'][name='commit'][value='save_as_draft_and_add_credentials']",
                    text: /Add AI credentials/
      assert_select "button[type='submit'][name='commit'][value='save_as_draft_and_add_search_credentials']",
                    text: /Add search credentials/
      assert_select "[data-key='credentials.gate.help']",
                    text: /save this feed as a draft and bring you back after each setup step/
    end
  end

  test "credential gate renders only the missing search credential action" do
    sign_in_as(user)
    create(:ai_credential, :active, user: user)

    get feed_preview_path(profile_key: "llm", "params" => { "prompt" => "https://example.com" })

    assert_response :success
    assert_select "button[value='save_as_draft_and_add_credentials']", count: 0
    assert_select "button[value='save_as_draft_and_add_search_credentials']"
  end

  test "credential gate does not include direct credential links" do
    sign_in_as(user)

    get feed_preview_path(profile_key: "llm", "params" => { "prompt" => "https://example.com" })

    assert_response :success
    assert_select "[data-key='credentials.gate'] a[href*='/ai_credentials/new']", false
    assert_select "[data-key='credentials.gate'] a[href*='/search_credentials/new']", false
  end
end
