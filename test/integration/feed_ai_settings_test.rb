require "test_helper"

# The feed form's AI Settings section: AI provider, search provider, and model
# selectors for AI-backed profiles. The dependent model dropdown is wired
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

  def search_credential
    @search_credential ||= create(:search_credential, :active, user: user, display_name: "Search key")
  end

  def ai_feed
    @ai_feed ||= create(:feed,
                        user: user,
                        feed_profile_key: "llm",
                        ai_credential: credential,
                        search_credential: search_credential,
                        ai_model: "claude-sonnet-4-6",
                        params: { "prompt" => "https://no-rss.example.com" })
  end

  def rss_feed
    @rss_feed ||= create(:feed, user: user, feed_profile_key: "rss")
  end

  test "#edit should show AI, search, and model selects for an AI feed" do
    sign_in_as(user)

    get edit_feed_path(ai_feed)

    assert_response :success
    assert_select "[data-key='form.ai-settings']"
    assert_select "[data-key='form.ai-settings'][hidden]", false
    assert_select "select[name='feed[ai_credential_id]'][data-key='form.ai-credential']"
    assert_select "select[name='feed[search_credential_id]'][data-key='form.search-credential']"
    assert_select "select[name='feed[ai_model]'][data-key='form.ai-model']"
    assert_select "[data-key='form.ai-model-unavailable']", false
  end

  test "#edit should warn when the feed's saved model is no longer available" do
    sign_in_as(user)
    stale_feed = create(:feed,
                        user: user,
                        feed_profile_key: "llm",
                        ai_credential: credential,
                        search_credential: search_credential,
                        ai_model: "removed-model",
                        params: { "prompt" => "https://no-rss.example.com" })

    get edit_feed_path(stale_feed)

    assert_select "[data-key='form.ai-model-unavailable']"
  end

  test "#edit should preselect the feed's saved credentials and model" do
    sign_in_as(user)

    get edit_feed_path(ai_feed)

    assert_select "select[data-key='form.ai-credential'] option[selected][value='#{credential.id}']"
    assert_select "select[data-key='form.search-credential'] option[selected][value='#{search_credential.id}']"
    assert_select "select[data-key='form.ai-model'] option[selected][value='claude-sonnet-4-6']", text: "Claude Sonnet 4.6"
  end

  test "#edit should prefer the user's default search credential when the feed has none" do
    sign_in_as(user)
    default = create(:search_credential, :active, :default, user: user, display_name: "Default search")
    create(:search_credential, :active, user: user, display_name: "Other search")
    feed = create(:feed,
                  user: user,
                  feed_profile_key: "llm",
                  ai_credential: credential,
                  search_credential: nil,
                  ai_model: "claude-sonnet-4-6",
                  params: { "prompt" => "https://no-rss.example.com" })

    get edit_feed_path(feed)

    assert_select "select[data-key='form.search-credential'] option[selected][value='#{default.id}']"
  end

  test "#edit should render the model placeholder as disabled so a pick can't be cleared" do
    sign_in_as(user)

    get edit_feed_path(ai_feed)

    assert_select "select[data-key='form.ai-model'] option[value=''][disabled][hidden]", text: "Select a model…"
    assert_select "select[data-key='form.ai-model'] option[value=''][selected]", false
  end

  test "#edit should select the placeholder when the saved model is no longer offered" do
    sign_in_as(user)
    stale_feed = create(:feed,
                        user: user,
                        feed_profile_key: "llm",
                        ai_credential: credential,
                        search_credential: search_credential,
                        ai_model: "removed-model",
                        params: { "prompt" => "https://no-rss.example.com" })

    get edit_feed_path(stale_feed)

    assert_select "select[data-key='form.ai-model'] option[value=''][selected][disabled]", text: "Select a model…"
    assert_select "select[data-key='form.ai-model'] option[selected]", count: 1
  end

  test "#edit should list only capability-matrix models in the model select" do
    sign_in_as(user)

    get edit_feed_path(ai_feed)

    assert_select "select[data-key='form.ai-model'] option", text: "Claude Sonnet 4.6"
    # Opus is offered by the credential but not in the matrix, so it's gated out.
    assert_select "select[data-key='form.ai-model'] option", text: "Claude Opus 4.7", count: 0
  end

  test "#edit should embed each credential's capability-matrix models for the dependent dropdown" do
    sign_in_as(user)

    get edit_feed_path(ai_feed)

    section = css_select("[data-key='form.ai-settings']").first
    embedded = JSON.parse(section["data-ai-settings-models-value"])
    # Only the verified Sonnet model survives the capability-matrix gate.
    assert_equal [{ "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" }], embedded[credential.id.to_s]

    ai_profiles = JSON.parse(section["data-ai-settings-ai-profiles-value"])
    assert_includes ai_profiles, "llm"
    assert_not_includes ai_profiles, "rss"
  end

  test "#edit should hide and disable the section for a non-AI feed" do
    sign_in_as(user)
    credential
    search_credential

    get edit_feed_path(rss_feed)

    assert_select "[data-key='form.ai-settings'][hidden]"
    assert_select "select[name='feed[ai_credential_id]'][disabled]"
    assert_select "select[name='feed[search_credential_id]'][disabled]"
    assert_select "select[name='feed[ai_model]'][disabled]"
  end

  test "#edit should show only the AI credential button when search credentials exist" do
    sign_in_as(user)
    search_credential
    feed_without_credential = create(:feed,
                                     user: user,
                                     feed_profile_key: "llm",
                                     ai_credential: nil,
                                     search_credential: search_credential,
                                     params: { "prompt" => "https://no-rss.example.com" })

    get edit_feed_path(feed_without_credential)

    assert_select "[data-key='credentials.gate']"
    assert_select "button[value='save_as_draft_and_add_credentials']"
    assert_select "button[value='save_as_draft_and_add_search_credentials']", count: 0
    assert_select "select[name='feed[ai_model]']", false
  end

  test "#edit should show only the search credential button when AI credentials exist" do
    sign_in_as(user)
    feed_without_search = create(:feed,
                                 user: user,
                                 feed_profile_key: "llm",
                                 ai_credential: credential,
                                 search_credential: nil,
                                 params: { "prompt" => "https://no-rss.example.com" })

    get edit_feed_path(feed_without_search)

    assert_select "button[value='save_as_draft_and_add_credentials']", count: 0
    assert_select "button[value='save_as_draft_and_add_search_credentials']"
  end

  test "#edit should lock the Enable checkbox off when AI credentials are missing" do
    sign_in_as(user)
    search_credential
    feed_without_credential = create(:feed,
                                     user: user,
                                     feed_profile_key: "llm",
                                     ai_credential: nil,
                                     search_credential: search_credential,
                                     params: { "prompt" => "https://no-rss.example.com" })

    get edit_feed_path(feed_without_credential)

    assert_select "input[type=checkbox][name='enable_feed'][disabled]", count: 1
    assert_select "input[type=checkbox][name='enable_feed'][checked]", false,
                  "Enable checkbox should be unchecked while enabling is unavailable"
    assert_select "[data-key='form.enable-blocked-note']", text: /AI credentials/
  end

  test "#edit should lock the Enable checkbox off when only search credentials are missing" do
    sign_in_as(user)
    feed_without_search = create(:feed,
                                 user: user,
                                 feed_profile_key: "llm",
                                 ai_credential: credential,
                                 search_credential: nil,
                                 params: { "prompt" => "https://no-rss.example.com" })

    get edit_feed_path(feed_without_search)

    assert_select "input[type=checkbox][name='enable_feed'][disabled]", count: 1
    assert_select "[data-key='form.enable-blocked-note']", text: /search credentials/
  end

  test "#edit should keep the Enable checkbox interactive when AI setup is complete" do
    sign_in_as(user)

    get edit_feed_path(ai_feed)

    assert_select "input[type=checkbox][name='enable_feed']:not([disabled])"
    assert_select "[data-key='form.enable-blocked-note']", false
  end
end
