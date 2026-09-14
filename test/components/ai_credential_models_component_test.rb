require "test_helper"
require "view_component/test_case"

class AiCredentialModelsComponentTest < ViewComponent::TestCase
  def render_models
    render_inline(AiCredentialModelsComponent.new(ai_credential: build(:ai_credential)))
  end

  test "#render should display SDK metadata and order models by name" do
    create(:llm_model, name: "Zulu", model_id: "zulu")
    create(:llm_model, name: "Alpha", model_id: "alpha", context_window: 1_050_000,
                       capabilities: %w[function_calling structured_output])
    create(:llm_model, provider: "anthropic", name: "Other provider")

    result = render_models

    assert_equal %w[Alpha Zulu], result.css('[data-key="ai_credential.model.name"]').map(&:text)
    assert_includes result.text, "1,050,000 token context"
    assert_includes result.text, "Tools: yes"
    assert_includes result.text, "Structured output: yes"
    assert_includes result.text, "Output: text"
  end

  test "#render should retain non-text models and leave missing capabilities unknown" do
    create(:llm_model, model_id: "embedding-model", modalities: { output: ["embeddings"] })

    result = render_models

    assert_includes result.text, "embedding-model"
    assert_includes result.text, "Output: embeddings"
    assert_includes result.text, "Tools: unknown"
  end

  test "#render should omit an empty provider catalog" do
    create(:llm_model, provider: "anthropic")

    assert_empty render_models.css('[data-key="ai_credential.models"]')
  end
end
