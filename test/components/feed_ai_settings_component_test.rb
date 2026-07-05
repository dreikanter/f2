require "test_helper"
require "view_component/test_case"

# The component's logic is tested directly (no form builder needed); the
# rendered markup is covered by test/integration/feed_ai_settings_test.rb.
class FeedAiSettingsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  # Anthropic's live snapshot offers both, but only Sonnet is in the capability
  # matrix — Opus stands in for an offered-but-unverified model gating drops.
  def models
    [
      { "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" },
      { "id" => "claude-opus-4-7", "name" => "Claude Opus 4.7" }
    ]
  end

  def credential
    @credential ||= create(:ai_credential, :active, user: user, available_models: models)
  end

  def unverified_credential
    @unverified_credential ||= create(:ai_credential, :active, user: user, provider: "openrouter",
                                                               available_models: [{ "id" => "anthropic/claude-sonnet-4-6" }])
  end

  def ai_feed(**attrs)
    build(:feed, user: user, feed_profile_key: "llm", params: { "prompt" => "x" }, **attrs)
  end

  def component(feed)
    FeedAiSettingsComponent.new(feed: feed, form: nil)
  end

  test "#section_visible? should be true only for an AI profile" do
    assert component(ai_feed).section_visible?
    assert_not component(build(:feed, user: user, feed_profile_key: "rss")).section_visible?
  end

  test "#credentials? should reflect whether the user has a selectable credential" do
    assert_not component(ai_feed).credentials?
    credential
    assert component(ai_feed).credentials?
  end

  test "#credentials? should be false when the only credential's provider has no matrix models" do
    unverified_credential
    assert_not component(ai_feed).credentials?
  end

  test "#models_by_credential should keep only capability-matrix models, mapped with names" do
    assert_equal(
      { credential.id.to_s => [{ "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" }] },
      component(ai_feed).models_by_credential
    )
  end

  test "#models_by_credential should fall back to the id when a model has no name" do
    credential.update!(available_models: [{ "id" => "claude-sonnet-4-6" }])
    assert_equal "claude-sonnet-4-6", component(ai_feed).models_by_credential[credential.id.to_s].first["name"]
  end

  test "#models_by_credential should drop a credential left with no matrix models" do
    credential.update!(available_models: [{ "id" => "claude-3-haiku-unverified", "name" => "Unverified" }])
    assert_empty component(ai_feed).models_by_credential
  end

  test "#selectable_credentials should exclude a credential whose provider has no matrix models" do
    credential
    unverified_credential
    ids = component(ai_feed).selectable_credentials.map(&:id)
    assert_includes ids, credential.id
    assert_not_includes ids, unverified_credential.id
  end

  test "#ai_profile_keys should list only AI-backed profiles" do
    keys = component(ai_feed).ai_profile_keys
    assert_includes keys, "llm"
    assert_not_includes keys, "rss"
  end

  test "#selected_credential_id should fall back to the user's default credential" do
    user.update!(default_ai_credential: credential)
    assert_equal credential.id.to_s, component(ai_feed(ai_credential: nil)).selected_credential_id
  end

  test "#selected_credential_id should skip a saved credential that isn't selectable" do
    credential
    assert_equal credential.id.to_s, component(ai_feed(ai_credential: unverified_credential)).selected_credential_id
  end

  test "#model_unavailable? should be true when the saved model is no longer offered" do
    feed = ai_feed(ai_credential: credential, ai_model: "removed-model")
    assert component(feed).model_unavailable?
  end

  test "#model_unavailable? should be true when the saved model is offered but not in the matrix" do
    feed = ai_feed(ai_credential: credential, ai_model: "claude-opus-4-7")
    assert component(feed).model_unavailable?
  end

  test "#model_unavailable? should be false when the saved model is offered and verified" do
    feed = ai_feed(ai_credential: credential, ai_model: "claude-sonnet-4-6")
    assert_not component(feed).model_unavailable?
  end

  test "#model_unavailable? should be false for a non-AI feed" do
    feed = build(:feed, user: user, feed_profile_key: "rss", ai_credential: credential, ai_model: "removed-model")
    assert_not component(feed).model_unavailable?
  end
end
