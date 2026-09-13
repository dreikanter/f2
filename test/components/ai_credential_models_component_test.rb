require "test_helper"
require "view_component/test_case"

class AiCredentialModelsComponentTest < ViewComponent::TestCase
  def models
    [
      {
        "id" => "gpt-5.6-luna",
        "name" => "GPT-5.6 Luna",
        "metadata" => { "context_window" => 1_050_000, "tool_call" => true, "structured_output" => true,
                        "output_modalities" => ["text"], "source" => "RubyLLM" }
      }
    ]
  end

  test "#render should list each available model" do
    credential = create(:ai_credential, :active, available_models: models)

    result = render_inline(AiCredentialModelsComponent.new(ai_credential: credential))

    assert_includes result.css('[data-key="ai_credential.model.name"]').first.text, "GPT-5.6 Luna"
  end

  test "#render should show context size and capabilities" do
    credential = create(:ai_credential, :active, available_models: models)

    result = render_inline(AiCredentialModelsComponent.new(ai_credential: credential))

    text = result.css('[data-key="ai_credential.model"]').first.text
    assert_includes text, "1,050,000 token context"
    assert_includes text, "Tools: yes"
    assert_includes text, "Structured output: yes"
    assert_includes text, "Output: text"
    assert_includes text, "Source: RubyLLM"
  end

  test "#render should fall back to the id when name is blank" do
    credential = create(:ai_credential, :active, available_models: [{ "id" => "some-model" }])

    result = render_inline(AiCredentialModelsComponent.new(ai_credential: credential))

    assert_includes result.css('[data-key="ai_credential.model.name"]').first.text, "some-model"
    assert_includes result.text, "Tools: unknown"
    assert_includes result.text, "Structured output: unknown"
  end

  test "#render should order models by provider then model name" do
    unordered = [
      { "id" => "z", "name" => "OpenAI: GPT-4" },
      { "id" => "a", "name" => "Google: Gemini Pro" },
      { "id" => "b", "name" => "Google: Gemini Flash" }
    ]
    credential = create(:ai_credential, :active, available_models: unordered)

    result = render_inline(AiCredentialModelsComponent.new(ai_credential: credential))

    names = result.css('[data-key="ai_credential.model.name"]').map { |node| node.text.strip }
    assert_equal ["Google: Gemini Flash", "Google: Gemini Pro", "OpenAI: GPT-4"], names
  end

  test "#render should render nothing when there are no models" do
    credential = create(:ai_credential, :active, available_models: [])

    result = render_inline(AiCredentialModelsComponent.new(ai_credential: credential))

    assert_empty result.css('[data-key="ai_credential.models"]')
  end

  test "#render should retain non-text models in the catalog with their output modalities" do
    credential = create(:ai_credential, :active, available_models: [{ "id" => "text-embedding-3-small", "metadata" => {
      "output_modalities" => ["embeddings"], "source" => "RubyLLM", "tool_call" => false, "structured_output" => false
    } }])

    result = render_inline(AiCredentialModelsComponent.new(ai_credential: credential))

    assert_includes result.text, "text-embedding-3-small"
    assert_includes result.text, "Output: embeddings"
    assert_includes result.text, "Tools: no"
    assert_includes result.text, "Structured output: no"
    assert_includes result.text, "Source: RubyLLM"
  end
end
