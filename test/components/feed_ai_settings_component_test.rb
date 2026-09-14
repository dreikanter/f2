require "test_helper"
require "view_component/test_case"

# The component's logic is tested directly (no form builder needed); the
# rendered markup is covered by test/integration/feed_ai_settings_test.rb.
class FeedAiSettingsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def models
    [{ "id" => "gpt-a", "name" => "Model A" }, { "id" => "gpt-b", "name" => "Model B" }]
  end

  def credential
    @credential ||= create(:ai_credential, :active, user: user)
  end

  def other_credential
    @other_credential ||= create(:ai_credential, :active, user: user)
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
    create(:llm_model, model_id: "gpt-a", name: "Model A")
    assert_not component(ai_feed).credentials?
    credential
    assert component(ai_feed).credentials?
  end

  test "#credentials? should include a newly listed provider model" do
    create(:llm_model, model_id: "gpt-a", name: "Model A")
    other_credential
    assert component(ai_feed).credentials?
  end

  test "#models_by_credential should offer all listed models, mapped with names" do
    create(:llm_model, model_id: "gpt-a", name: "Model A")
    create(:llm_model, model_id: "gpt-b", name: "Model B")
    assert_equal(
      { credential.id.to_s => models },
      component(ai_feed).models_by_credential
    )
  end

  test "#models_by_credential should share the provider catalog between credentials" do
    create(:llm_model, model_id: "gpt-a", name: "Model A")
    first = credential
    second = other_credential
    lists = component(ai_feed).models_by_credential

    assert_equal lists.fetch(first.id.to_s), lists.fetch(second.id.to_s)
  end

  test "#ai_profile_keys should list only AI-backed profiles" do
    keys = component(ai_feed).ai_profile_keys
    assert_includes keys, "llm"
    assert_not_includes keys, "rss"
  end

  test "#selected_credential_id should fall back to the user's default credential" do
    create(:llm_model, model_id: "gpt-a", name: "Model A")
    user.update!(default_ai_credential: credential)
    assert_equal credential.id.to_s, component(ai_feed(ai_credential: nil)).selected_credential_id
  end

  test "#selected_credential_id should keep a saved credential with newly listed models" do
    create(:llm_model, model_id: "gpt-b", name: "Model B")
    credential
    assert_equal other_credential.id.to_s, component(ai_feed(ai_credential: other_credential)).selected_credential_id
  end

  test "#model_select_options should lead with a disabled hidden placeholder" do
    create(:llm_model, model_id: "gpt-a", name: "Model A")
    create(:llm_model, model_id: "gpt-b", name: "Model B")
    options = component(ai_feed(ai_credential: credential)).model_select_options
    assert_equal ["Select a model…", "", { disabled: true, hidden: true }], options.first
    assert_equal [["Model A", "gpt-a"], ["Model B", "gpt-b"]], options.drop(1)
  end

  test "#selected_model_id should return the saved model when it's still offered" do
    create(:llm_model, model_id: "gpt-a", name: "Model A")
    feed = ai_feed(ai_credential: credential, ai_model: "gpt-a")
    assert_equal "gpt-a", component(feed).selected_model_id
  end

  test "#selected_model_id should preserve a saved model absent from the listing" do
    create(:llm_model, model_id: "gpt-b", name: "Model B")
    feed = ai_feed(ai_credential: credential, ai_model: "gpt-b")
    feed.ai_model = "removed-model"
    assert_equal "removed-model", component(feed).selected_model_id
  end

  test "#model_unavailable? should be true when the saved model is no longer offered" do
    create(:llm_model, model_id: "gpt-a", name: "Model A")
    feed = ai_feed(ai_credential: credential, ai_model: "removed-model")
    assert component(feed).model_unavailable?
  end

  test "#model_unavailable? should be false for a newly listed model" do
    create(:llm_model, model_id: "gpt-b", name: "Model B")
    feed = ai_feed(ai_credential: credential, ai_model: "gpt-b")
    assert_not component(feed).model_unavailable?
  end

  test "#model_unavailable? should be false when the saved model is offered" do
    create(:llm_model, model_id: "gpt-a", name: "Model A")
    feed = ai_feed(ai_credential: credential, ai_model: "gpt-a")
    assert_not component(feed).model_unavailable?
  end

  test "#model_unavailable? should be false for a non-AI feed" do
    feed = build(:feed, user: user, feed_profile_key: "rss", ai_credential: credential, ai_model: "removed-model")
    assert_not component(feed).model_unavailable?
  end

  test "#models_by_credential should omit non-text models from new choices while retaining a saved selection" do
    create(:llm_model, model_id: "image-model", modalities: { output: ["image"] })
    create(:llm_model, model_id: "future-model", modalities: {}, capabilities: [])
    fresh = component(ai_feed(ai_credential: credential))
    saved = component(ai_feed(ai_credential: credential, ai_model: "image-model"))

    assert_equal ["future-model"], fresh.models_by_credential.fetch(credential.id.to_s).pluck("id")
    assert_equal ["future-model", "image-model"], saved.models_by_credential.fetch(credential.id.to_s).pluck("id")
    assert_equal "image-model", saved.selected_model_id
    assert saved.model_unavailable?
  end
end
