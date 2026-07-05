require "test_helper"
require "view_component/test_case"

# The component's logic is tested directly (no form builder needed); the
# rendered markup is covered by test/integration/feed_ai_settings_test.rb.
class FeedAiSettingsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  # Intentionally not name-sorted, to prove #models_by_credential sorts them.
  def models
    [
      { "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" },
      { "id" => "claude-opus-4-7", "name" => "Claude Opus 4.7" }
    ]
  end

  def credential
    @credential ||= create(:ai_credential, :active, user: user, available_models: models)
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

  test "#credentials? should reflect whether the user has active credentials" do
    assert_not component(ai_feed).credentials?
    credential
    assert component(ai_feed).credentials?
  end

  test "#models_by_credential should key each credential to its name-sorted models" do
    expected = {
      credential.id.to_s => [
        { "id" => "claude-opus-4-7", "name" => "Claude Opus 4.7" },
        { "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" }
      ]
    }
    assert_equal expected, component(ai_feed).models_by_credential
  end

  test "#models_by_credential should fall back to the id when a model has no name" do
    credential.update!(available_models: [{ "id" => "claude-sonnet-4-6" }])
    assert_equal "claude-sonnet-4-6", component(ai_feed).models_by_credential[credential.id.to_s].first["name"]
  end

  test "#models_by_credential should drop models not in the capability matrix" do
    credential.update!(available_models: [
      { "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" },
      { "id" => "claude-3-haiku-unverified", "name" => "Unverified" }
    ])
    ids = component(ai_feed).models_by_credential[credential.id.to_s].map { |model| model["id"] }
    assert_equal ["claude-sonnet-4-6"], ids
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

  test "#model_unavailable? should be true when the saved model is no longer offered" do
    feed = ai_feed(ai_credential: credential, ai_model: "removed-model")
    assert component(feed).model_unavailable?
  end

  test "#model_unavailable? should be false when the saved model is still offered" do
    feed = ai_feed(ai_credential: credential, ai_model: "claude-sonnet-4-6")
    assert_not component(feed).model_unavailable?
  end

  test "#model_unavailable? should be false for a non-AI feed" do
    feed = build(:feed, user: user, feed_profile_key: "rss", ai_credential: credential, ai_model: "removed-model")
    assert_not component(feed).model_unavailable?
  end
end
