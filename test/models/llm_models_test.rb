require "test_helper"

class LlmModelsTest < ActiveSupport::TestCase
  teardown { RubyLLM.models.load_from_json }

  test "#for_provider should use the configured catalog before the first refresh without network requests" do
    assert_empty RubyLLM::ActiveRecord::Model.all
    RubyLLM.models.load_from_store
    cached_models = RubyLLM.models.all

    assert_includes LlmModels.for_provider("openai").map(&:id), "gpt-5.6-luna"
    assert_equal cached_models, RubyLLM.models.all
    assert_empty RubyLLM.models.all
    assert_not_requested :any, /./
  end

  test "#for_provider should read current database rows despite a stale SDK process cache" do
    record = create(:llm_model, model_id: "shared-model", name: "Before refresh")
    RubyLLM.models.load_from_store
    record.update!(name: "After refresh")
    create(:llm_model, provider: "anthropic")
    create(:llm_model, model_id: "unlisted-model", unlisted_at: Time.current)

    assert_equal "Before refresh", RubyLLM.models.find("shared-model", provider: :openai).name
    assert_equal [["shared-model", "After refresh"]], LlmModels.for_provider("openai").map { |model| [model.id, model.name] }
  end

  test "#for_provider should respect an empty provider list in a populated registry" do
    create(:llm_model, provider: "anthropic")

    assert_empty LlmModels.for_provider("openai")
  end

  test "#counts_by_provider should separate listed models from unlisted leftovers" do
    create(:llm_model, provider: "openai")
    create(:llm_model, provider: "openai", unlisted_at: Time.current)
    create(:llm_model, provider: "anthropic")

    assert_equal [
      { provider: "anthropic", listed: 1, unlisted: 0 },
      { provider: "openai", listed: 1, unlisted: 1 }
    ], LlmModels.counts_by_provider
  end

  test "#for_feed should exclude known non-text models and preserve missing metadata" do
    create(:llm_model, model_id: "text")
    create(:llm_model, model_id: "image", modalities: { output: ["image"] })
    create(:llm_model, model_id: "unknown", modalities: {})

    assert_equal %w[text unknown], LlmModels.for_feed("openai").map(&:id).sort
  end
end
