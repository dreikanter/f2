require "test_helper"

# Integration test for the credential gate as a form-submit button.
# Renders the gate from the feed-preview turbo-frame (inside the feed
# form) and asserts the button and help-text shape that the
# FeedsController#create handler keys off in T506.
class CredentialGateTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  test "credential gate renders as form-submit button with help text when AI profile lacks credentials" do
    sign_in_as(user)

    get feed_preview_path(profile_key: "llm_website_extractor", "params" => { "url" => "https://example.com" })

    assert_response :success
    assert_select "[data-key='credentials.gate']" do
      assert_select "button[type='submit'][name='commit'][value='save_as_draft_and_add_credentials']",
                    text: /Add AI credentials/
      assert_select "[data-key='credentials.gate.help']",
                    text: /We'll save your feed as a draft so you can pick up where you left off\./
    end
  end

  test "credential gate does not include a stray link to new_ai_credential_path" do
    sign_in_as(user)

    get feed_preview_path(profile_key: "llm_website_extractor", "params" => { "url" => "https://example.com" })

    assert_response :success
    assert_select "[data-key='credentials.gate'] a[href*='/ai_credentials/new']", false
  end
end
