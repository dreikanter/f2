require "test_helper"

# The feed form's AI Settings section: the provider + model selectors that
# appear for AI-backed profiles. The dependent model dropdown is wired
# client-side from an embedded models map, so these tests assert the
# server-rendered contract the Stimulus controller relies on.
class FeedAiSettingsTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def models
    [
      { "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" },
      { "id" => "claude-opus-4-7", "name" => "Claude Opus 4.7" }
    ]
  end

  def credential
    @credential ||= create(:ai_credential, :active, user: user, display_name: "Main key", available_models: models)
  end

  def ai_feed
    @ai_feed ||= create(:feed,
                        user: user,
                        feed_profile_key: "llm_website_extractor",
                        ai_credential: credential,
                        ai_model: "claude-sonnet-4-6",
                        params: { "url" => "https://no-rss.example.com" })
  end

  def rss_feed
    @rss_feed ||= create(:feed, user: user, feed_profile_key: "rss")
  end

  test "#edit should show the AI Settings section with provider and model selects for an AI feed" do
    sign_in_as(user)
    credential

    get edit_feed_path(ai_feed)

    assert_response :success
    assert_select "[data-key='form.ai-settings']"
    assert_select "[data-key='form.ai-settings'][hidden]", false
    assert_select "select[name='feed[ai_credential_id]'][data-key='form.ai-credential']"
    assert_select "select[name='feed[ai_model]'][data-key='form.ai-model']"
    assert_select "[data-key='form.ai-model-unavailable']", false
  end

  test "#edit should warn when the feed's saved model is no longer available" do
    sign_in_as(user)
    stale_feed = create(:feed,
                        user: user,
                        feed_profile_key: "llm_website_extractor",
                        ai_credential: credential,
                        ai_model: "removed-model",
                        params: { "url" => "https://no-rss.example.com" })

    get edit_feed_path(stale_feed)

    assert_select "[data-key='form.ai-model-unavailable']"
  end

  test "#edit should preselect the feed's saved provider and model" do
    sign_in_as(user)

    get edit_feed_path(ai_feed)

    assert_select "select[data-key='form.ai-credential'] option[selected][value='#{credential.id}']"
    assert_select "select[data-key='form.ai-model'] option[selected][value='claude-sonnet-4-6']", text: "Claude Sonnet 4.6"
  end

  test "#edit should list the selected credential's models in the model select" do
    sign_in_as(user)

    get edit_feed_path(ai_feed)

    assert_select "select[data-key='form.ai-model'] option", text: "Claude Sonnet 4.6"
    assert_select "select[data-key='form.ai-model'] option", text: "Claude Opus 4.7"
  end

  test "#edit should embed every active credential's models for the dependent dropdown" do
    sign_in_as(user)

    get edit_feed_path(ai_feed)

    section = css_select("[data-key='form.ai-settings']").first
    embedded = JSON.parse(section["data-ai-settings-models-value"])
    # Sorted by display name, matching how the model select lists them.
    assert_equal models.sort_by { |model| model["name"] }, embedded[credential.id.to_s]

    ai_profiles = JSON.parse(section["data-ai-settings-ai-profiles-value"])
    assert_includes ai_profiles, "llm_website_extractor"
    assert_not_includes ai_profiles, "rss"
  end

  test "#edit should hide and disable the section for a non-AI feed" do
    sign_in_as(user)
    credential

    get edit_feed_path(rss_feed)

    assert_select "[data-key='form.ai-settings'][hidden]"
    assert_select "select[name='feed[ai_credential_id]'][disabled]"
    assert_select "select[name='feed[ai_model]'][disabled]"
  end

  test "#edit should show the credential gate when the user has no active credentials" do
    sign_in_as(user)
    feed_without_credential = create(:feed,
                                     user: user,
                                     feed_profile_key: "llm_website_extractor",
                                     ai_credential: nil,
                                     params: { "url" => "https://no-rss.example.com" })

    get edit_feed_path(feed_without_credential)

    assert_select "[data-key='credentials.gate']"
    assert_select "button[value='save_as_draft_and_add_credentials']"
    assert_select "select[name='feed[ai_model]']", false
  end
end
