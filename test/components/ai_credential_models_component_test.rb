require "test_helper"
require "view_component/test_case"

class AiCredentialModelsComponentTest < ViewComponent::TestCase
  def models
    [
      {
        "id" => "claude-sonnet-4-6",
        "name" => "Claude Sonnet 4.6",
        "context_window" => 200_000,
        "capabilities" => ["function_calling"]
      }
    ]
  end

  test "#render should list each available model" do
    credential = create(:ai_credential, :active, available_models: models)

    result = render_inline(AiCredentialModelsComponent.new(ai_credential: credential))

    assert_includes result.css('[data-key="ai_credential.model.name"]').first.text, "Claude Sonnet 4.6"
  end

  test "#render should show context size and capabilities" do
    credential = create(:ai_credential, :active, available_models: models)

    result = render_inline(AiCredentialModelsComponent.new(ai_credential: credential))

    text = result.css('[data-key="ai_credential.model"]').first.text
    assert_includes text, "200,000 token context"
    assert_includes text, "function calling"
  end

  test "#render should fall back to the id when name is blank" do
    credential = create(:ai_credential, :active, available_models: [{ "id" => "some-model" }])

    result = render_inline(AiCredentialModelsComponent.new(ai_credential: credential))

    assert_includes result.css('[data-key="ai_credential.model.name"]').first.text, "some-model"
  end

  test "#render should render nothing when there are no models" do
    credential = create(:ai_credential, :active, available_models: [])

    result = render_inline(AiCredentialModelsComponent.new(ai_credential: credential))

    assert_empty result.css('[data-key="ai_credential.models"]')
  end
end
